"""Reconstruct Google Photos album structure inside Immich after a Takeout extract.

The problem this solves
-----------------------
Takeout files a photo TWICE: once under "Photos from <year>" and again under
every album it belongs to. Immich's external library indexes by *path*, so
pointing importPaths at the album folders too would create a second asset for
every photo in an album - about 8,900 duplicates here.

But an Immich album is a database row, not a directory. So the album structure
can be rebuilt against the assets Immich ALREADY has from the year folders,
costing no extra bytes and creating no duplicates. Only the files that exist
*solely* in an album folder (875 of 9,803 here) actually need uploading.

Three things it does, in order
-----------------------------
1. Refreshes the library's importPaths from what is on disk.
   ⚠️ This is the bug that motivated the whole script. importPaths was a
   hardcoded list of 19 "Photos from <year>" directories. It covered 2005 and
   2009-2026, so a photo taken in 2006-2008 landed on disk and was SILENTLY
   invisible, and "Photos from 2027" would have been invisible from January.
   Same shape as the /var/lib backup gap: a rule written as an explicit list
   that quietly stops covering things as reality grows. Regenerating it from
   disk every run means it cannot drift again.

2. Rebuilds albums, mapping Google's semantics onto Immich's rather than
   flattening them:
       Archive        -> visibility=archive   (hidden from the timeline, still yours)
       Locked Folder  -> visibility=locked    (PIN-gated; see the warning below)
       Bin            -> skipped entirely
       anything else  -> a normal album

3. Uploads the album-only orphans and files them into the same album.

⚠️ LOCKING IS ONE-WAY FROM A SCRIPT, VERIFIED 2026-10-03.
An API key can set visibility=locked, but once locked the asset is invisible to
that key - unlocking returns 400 "Not found or no asset.update access", because
the locked folder is a real boundary and not a flag. Undoing it needs the app
with the PIN. So locking sits behind its own --include-locked flag and is never
part of a default run. Found by testing on one asset rather than on 135.

Idempotent by content: every uploaded file is recorded by sha256, so a re-run
after the next Takeout imports only what is new. Albums are matched by name and
added to rather than recreated.

Usage:
    takeout-photos-sync                    # dry run, changes nothing
    takeout-photos-sync --apply            # albums + archive + orphan uploads
    takeout-photos-sync --apply --include-locked   # also moves Locked Folder
"""

import hashlib
import json
import mimetypes
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

PHOTOS = Path("/tank/backup/google/photos")
API = "http://127.0.0.1:2283/api"
KEY_FILE = Path("/var/lib/morty-backup/immich-takeout-sync.key")
STATE = Path("/fast/data/takeout-photos-sync")
UPLOADED = STATE / "uploaded.sha256"

YEAR_PREFIX = "Photos from "

# Folder name -> Immich visibility. Everything not named here becomes a normal
# album at visibility=timeline.
ARCHIVE_DIRS = {"Archive"}
LOCKED_DIRS = {"Locked Folder"}
SKIP_DIRS = {"Bin"}

# Takeout writes a sidecar per media file and a few bookkeeping files at the top
# level. None of them are assets.
SIDECAR_SUFFIXES = (".json",)
# The video half of a Google motion photo. Not a standalone asset, and counting
# them inflated the orphan figure by 17 before this exclusion.
MOTION_SUFFIX = ".MP"

DRY_RUN = "--apply" not in sys.argv
INCLUDE_LOCKED = "--include-locked" in sys.argv


def log(*a):
    print(*a, flush=True)


def api(path, method="GET", body=None, raw=None, content_type=None):
    url = f"{API}{path}"
    data = None
    headers = {"x-api-key": KEY}
    if raw is not None:
        data = raw
        headers["Content-Type"] = content_type
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            text = r.read().decode()
            return json.loads(text) if text.strip() else None
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path} -> {e.code}: {e.read().decode()[:300]}") from None


def psql(sql):
    """Read path. Writes go through the API so Immich maintains its own invariants."""
    out = subprocess.run(
        ["runuser", "-u", "postgres", "--", "psql", "-d", "immich", "-At", "-F", "\x1f", "-c", sql],
        capture_output=True, text=True, check=True,
    ).stdout
    return [line.split("\x1f") for line in out.splitlines() if line]


# --- step 1: importPaths ----------------------------------------------------

def refresh_import_paths():
    lib = api("/libraries")[0]
    on_disk = sorted(str(p) for p in PHOTOS.glob(f"{YEAR_PREFIX}*") if p.is_dir())
    current = sorted(lib["importPaths"])
    if on_disk == current:
        log(f"importPaths: {len(current)} year folders, already current")
        return lib["id"], False
    added = [p for p in on_disk if p not in current]
    removed = [p for p in current if p not in on_disk]
    for p in added:
        log(f"  + {Path(p).name}")
    for p in removed:
        log(f"  - {Path(p).name}")
    if DRY_RUN:
        log(f"importPaths: WOULD set {len(on_disk)} paths ({len(added)} added, {len(removed)} removed)")
        return lib["id"], False
    api(f"/libraries/{lib['id']}", "PUT", {"importPaths": on_disk})
    api(f"/libraries/{lib['id']}/scan", "POST")
    log(f"importPaths: set {len(on_disk)} paths, scan triggered")
    return lib["id"], True


# --- step 2: index what Immich already has ----------------------------------

def index_assets():
    """basename (lowercased) -> list of (asset id, originalPath).

    The path is carried because filename alone is ambiguous for ~8,900 files:
    Takeout exports a photo that the phone ALSO uploaded, so the same basename
    exists twice - once as an external-library asset under "Photos from <year>"
    and once as a phone upload. Verified 2026-10-03: 8,877 of 8,940 duplicate
    basenames are exactly one of each. resolve() below uses the path to pick the
    Takeout copy, which is the one an album folder is actually duplicating, so
    these resolve exactly instead of being guessed or skipped."""
    rows = psql(
        'select "originalFileName", id, "originalPath" from asset where "deletedAt" is null'
    )
    idx = defaultdict(list)
    for name, aid, path in rows:
        idx[name.lower()].append((aid, path))
    log(f"indexed {len(rows)} assets, {len(idx)} distinct filenames")
    return idx


YEAR_ROOT = str(PHOTOS / YEAR_PREFIX)


def resolve(hits):
    """Pick one asset for an album entry. Returns (id, ambiguous?)."""
    if len(hits) == 1:
        return hits[0][0], False
    # Prefer the Takeout year-folder copy: it is the same file the album folder
    # holds a second time, so this is an exact identification, not a preference.
    takeout = [h for h in hits if h[1] and h[1].startswith(YEAR_ROOT)]
    if len(takeout) == 1:
        return takeout[0][0], False
    if takeout:
        return takeout[0][0], True
    return hits[0][0], True


def is_media(p: Path):
    if p.name.startswith("."):
        return False
    if p.suffix in SIDECAR_SUFFIXES:
        return False
    if p.suffix == MOTION_SUFFIX:
        return False
    return p.is_file()


def album_title(d: Path):
    """Google records the display title in metadata.json. An EMPTY title means
    this folder is a *conversation* - a direct share with comments, not an album
    (verified: "Angus, Andy" has title "" and a sharedAlbumComments array). Those
    are not albums and are skipped."""
    meta = d / "metadata.json"
    if meta.exists():
        try:
            m = json.loads(meta.read_text())
        except (json.JSONDecodeError, OSError):
            return d.name
        title = (m.get("title") or "").strip()
        if not title and "sharedAlbumComments" in m:
            return None  # conversation, not an album
        return title or d.name
    return d.name


def taken_at(p: Path):
    """photoTakenTime from the Takeout sidecar when present, else file mtime.
    Immich requires both dates on upload and will otherwise reject the file."""
    for cand in (
        p.with_name(p.name + ".supplemental-metadata.json"),
        p.with_suffix(p.suffix + ".json"),
    ):
        if cand.exists():
            try:
                m = json.loads(cand.read_text())
                ts = m.get("photoTakenTime", {}).get("timestamp")
                if ts:
                    return int(ts)
            except (json.JSONDecodeError, OSError, ValueError):
                pass
    return int(p.stat().st_mtime)


_SHA_CACHE = {}


def sha256(p: Path):
    """Cached: every candidate is hashed once to test the seen-set and again on
    upload, and some of these are 40 MB videos on spinning disks."""
    key = str(p)
    if key not in _SHA_CACHE:
        h = hashlib.sha256()
        with p.open("rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        _SHA_CACHE[key] = h.hexdigest()
    return _SHA_CACHE[key]


# --- step 3: upload an orphan ----------------------------------------------

def upload(p: Path):
    ts = taken_at(p)
    iso = datetime.fromtimestamp(ts, timezone.utc).isoformat().replace("+00:00", "Z")
    boundary = "----immich" + uuid.uuid4().hex
    ctype = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
    parts = []

    def field(name, value):
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode()
        )

    field("deviceAssetId", f"takeout-{sha256(p)[:16]}")
    field("deviceId", "takeout-photos-sync")
    field("fileCreatedAt", iso)
    field("fileModifiedAt", iso)
    parts.append(
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"assetData\"; "
        f"filename=\"{p.name}\"\r\nContent-Type: {ctype}\r\n\r\n".encode()
    )
    parts.append(p.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    r = api("/assets", "POST", raw=b"".join(parts),
            content_type=f"multipart/form-data; boundary={boundary}")
    return r["id"], r.get("status")


# --- main ------------------------------------------------------------------

def main():
    STATE.mkdir(parents=True, exist_ok=True)
    seen = set(UPLOADED.read_text().split()) if UPLOADED.exists() else set()

    log(f"=== takeout-photos-sync ({'DRY RUN' if DRY_RUN else 'APPLY'}) ===")
    refresh_import_paths()
    idx = index_assets()

    existing_albums = {a["albumName"]: a["id"] for a in (api("/albums") or [])}

    plan = []          # (title, visibility, [asset ids], [paths to upload])
    ambiguous = []
    conversations = []

    for d in sorted(PHOTOS.iterdir()):
        if not d.is_dir() or d.name.startswith(YEAR_PREFIX):
            continue
        if d.name in SKIP_DIRS:
            log(f"skip  {d.name}")
            continue

        title = album_title(d)
        if title is None:
            conversations.append(d.name)
            continue

        if d.name in ARCHIVE_DIRS:
            visibility, make_album = "archive", False
        elif d.name in LOCKED_DIRS:
            visibility, make_album = "locked", False
        else:
            visibility, make_album = None, True

        ids, to_upload = [], []
        for f in sorted(d.iterdir()):
            if not is_media(f):
                continue
            hits = idx.get(f.name.lower(), [])
            if hits:
                aid, unsure = resolve(hits)
                ids.append(aid)
                if unsure:
                    ambiguous.append((d.name, f.name, len(hits)))
            elif sha256(f) not in seen:
                to_upload.append(f)
        plan.append((title, visibility, make_album, ids, to_upload))

    # --- report ---
    log("")
    log(f"{'album':<28} {'matched':>8} {'upload':>7}  target")
    for title, vis, make_album, ids, up in plan:
        target = vis or "album"
        log(f"{title[:27]:<28} {len(ids):>8} {len(up):>7}  {target}")
    log("")
    log(f"conversations skipped (direct shares, not albums): {len(conversations)}")
    log(f"ambiguous filenames needing review: {len(ambiguous)}")
    for a in ambiguous[:10]:
        log(f"  {a[0]}/{a[1]} matches {a[2]} assets")
    total_up = sum(len(u) for _, _, _, _, u in plan)
    log(f"total to upload: {total_up}")

    if DRY_RUN:
        log("\nDRY RUN - nothing written. Re-run with --apply.")
        return

    # --- apply ---
    # The seen-set is appended per file rather than once at the end: a crash
    # part-way through 915 uploads would otherwise lose the record of everything
    # already sent. Immich also dedupes on checksum, so a repeat is harmless
    # rather than duplicating - but belt and braces, and it makes a resumed run
    # fast instead of re-hashing and re-sending.
    seen_fh = UPLOADED.open("a")
    for title, vis, make_album, ids, up in plan:
        if vis == "locked" and not INCLUDE_LOCKED:
            log(f"SKIP locked group '{title}' - needs --include-locked (one-way, see header)")
            continue

        for f in up:
            try:
                aid, status = upload(f)
                ids.append(aid)
                seen_fh.write(sha256(f) + "\n")
                seen_fh.flush()
                log(f"  uploaded {f.name} ({status})")
            except RuntimeError as e:
                log(f"  FAILED {f.name}: {e}")

        if not ids:
            continue

        if make_album:
            if title in existing_albums:
                album_id = existing_albums[title]
            else:
                album_id = api("/albums", "POST", {"albumName": title})["id"]
                existing_albums[title] = album_id
            for i in range(0, len(ids), 500):
                api(f"/albums/{album_id}/assets", "PUT", {"ids": ids[i:i + 500]})
            log(f"album '{title}': {len(ids)} assets")
        else:
            for i in range(0, len(ids), 500):
                api("/assets", "PUT", {"ids": ids[i:i + 500], "visibility": vis})
            log(f"{vis}: {len(ids)} assets from '{title}'")

    seen_fh.close()
    log("done")


if __name__ == "__main__":
    KEY = KEY_FILE.read_text().strip()
    main()
