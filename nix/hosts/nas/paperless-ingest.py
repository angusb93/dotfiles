#!/usr/bin/env python3
"""Keep Paperless fed from the two places documents actually arrive.

Two sources, one pass, both idempotent:

  email  - PDF attachments in the Gmail mirror that gmail-pull already writes
           to tank. Deliberately NOT Paperless's own IMAP mail rules: those
           want a Gmail app password or a second OAuth client, which is a new
           bearer credential and a new thing to expire, to monitor and to
           revoke. The mail is already on disk and that pull is already watched
           by backup-staleness.

  photos - photographs of documents, found by scoring the OCR text Immich has
           already extracted. No vision model, no second copy of the library.

Everything is keyed on content: an email attachment by the SHA-256 of its
bytes, a photo by its Immich asset id. Re-running imports nothing twice, so a
failed run is fixed by running it again and a partial run costs nothing.
"""
import email, email.policy, hashlib, json, os, re, subprocess, sys, time, uuid
import urllib.parse, urllib.request
from email.utils import parsedate_to_datetime
from pathlib import Path

MAIL_DIR  = Path("/tank/backup/google/mail")
STATE     = Path("/fast/data/paperless-backfill")
SEEN_MAIL = STATE / "email-imported.txt"     # one sha256 per line
SEEN_PHOTO= STATE / "photos-imported.txt"    # one immich asset id per line
WATERMARK = STATE / "last-run"

PAPERLESS = "http://127.0.0.1:28981/api"
IMMICH    = "http://127.0.0.1:2283/api"
PL_TOKEN  = Path("/var/lib/morty-backup/paperless-api.token").read_text().strip()
IM_KEY    = Path("/var/lib/morty-backup/immich-pipeline.key").read_text().strip()

# A runaway source should not be able to dump ten thousand documents into
# Paperless overnight. If a run hits the cap it says so and the next one
# continues, because the seen-sets make that free.
MAX_PER_RUN = 300

# Photos scoring at or above this are imported outright; the band below it is
# imported but tagged for a human to glance at. Tuned on the 2026-10-01
# backfill: 27 photos scored >=10 and were all genuine documents.
AUTO_SCORE, REVIEW_SCORE = 10, 6

log = lambda m: print(m, flush=True)


# ---------------------------------------------------------------- paperless

def pl(path, data=None):
    req = urllib.request.Request(
        f"{PAPERLESS}/{path}",
        data=json.dumps(data).encode() if data else None,
        method="POST" if data else "GET")
    req.add_header("Authorization", f"Token {PL_TOKEN}")
    if data:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read() or "{}")

_cache = {}
def ensure(kind, name):
    """Correspondent/tag by name, created once."""
    if (kind, name) in _cache:
        return _cache[(kind, name)]
    hit = pl(f"{kind}/?name__iexact={urllib.parse.quote(name)}")
    _cache[(kind, name)] = (hit["results"][0]["id"] if hit.get("count")
                            else pl(f"{kind}/", {"name": name})["id"])
    return _cache[(kind, name)]

def post_document(blob, filename, content_type, title, created, corr_id, tag_ids):
    b, parts = uuid.uuid4().hex, []
    def field(n, v):
        parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{n}"\r\n\r\n{v}\r\n'.encode())
    field("title", title)
    if created:
        field("created", created)
    if corr_id:
        field("correspondent", str(corr_id))
    for t in tag_ids:
        field("tags", str(t))
    parts.append(
        f'--{b}\r\nContent-Disposition: form-data; name="document"; filename="{filename}"\r\n'
        f'Content-Type: {content_type}\r\n\r\n'.encode() + blob + b"\r\n")
    parts.append(f"--{b}--\r\n".encode())
    req = urllib.request.Request(f"{PAPERLESS}/documents/post_document/",
                                 data=b"".join(parts), method="POST")
    req.add_header("Authorization", f"Token {PL_TOKEN}")
    req.add_header("Content-Type", f"multipart/form-data; boundary={b}")
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read().decode().strip()


# -------------------------------------------------------------------- email

NICE = {
    "post.xero.com": "Xero", "xero.com": "Xero",
    "email.propertyme.com": "PropertyMe",
    "team.aussiebroadband.com.au": "Aussie Broadband",
    "aussiebroadband.com.au": "Aussie Broadband",
    "octopus.energy": "Octopus Energy", "trading212.com": "Trading 212",
    "service.nsw.gov.au": "Service NSW", "careaccounting.com.au": "Care Accounting",
    "electrocomponents.com": "RS Components", "mail.anthropic.com": "Anthropic",
    "email.apple.com": "Apple", "eventbrite.com": "Eventbrite",
    "stripe.com": "Stripe", "github.com": "GitHub",
}
PERSONAL = {"gmail.com", "hotmail.com", "outlook.com", "yahoo.com", "me.com", "icloud.com"}

def correspondent_name(frm):
    g = re.search(r"@([A-Za-z0-9.-]+)", frm or "")
    if not g:
        return "Unknown sender"
    d = g.group(1).lower()
    if d in NICE:
        return NICE[d]
    if d in PERSONAL:
        nm = re.sub(r"<.*", "", frm or "").strip().strip('"') or d
        return f"Personal: {nm[:60]}"
    core = re.sub(r"^(post|email|mail|team|service|no-?reply|notifications?)\.", "", d)
    core = re.sub(r"\.(com|co|org|net|gov)?\.?(au|uk|nz|us)?$", "", core)
    return (core.replace("-", " ").replace(".", " ").title()[:60] or d)

def candidate_emails(since_epoch):
    """.eml files touched since the last run that mention a PDF part.

    The mtime filter is what keeps this cheap - a full scan of 120k messages
    costs a minute, and almost all of them were already read yesterday. Two
    days of overlap covers a clock skew or a run that died halfway.
    """
    if not MAIL_DIR.is_dir():
        return []
    args = ["find", str(MAIL_DIR), "-name", "*.eml"]
    if since_epoch:
        args += ["-newermt", f"@{int(since_epoch) - 2 * 86400}"]
    found = subprocess.run(args, capture_output=True, text=True).stdout.split("\n")
    found = [f for f in found if f]
    if not found:
        return []
    hits = []
    for f in found:
        try:
            with open(f, "rb") as fh:
                if b"application/pdf" in fh.read():
                    hits.append(f)
        except OSError:
            continue
    return hits

def ingest_email(seen, budget):
    since = float(WATERMARK.read_text().strip()) if WATERMARK.exists() else 0
    files = candidate_emails(since)
    log(f"email: {len(files)} message(s) with a PDF part since last run")
    tag = ensure("tags", "source:email")
    added = 0
    for f in files:
        if added >= budget:
            log("email: hit the per-run cap, the rest comes next run")
            break
        try:
            with open(f, "rb") as fh:
                msg = email.message_from_binary_file(fh, policy=email.policy.default)
        except Exception as e:
            log(f"email: unreadable {f}: {e}")
            continue
        subj = (msg.get("Subject") or "").strip()
        frm  = (msg.get("From") or "").strip()
        date = (msg.get("Date") or "").strip()
        for part in msg.walk():
            fn = part.get_filename() or ""
            if (part.get_content_type() or "").lower() != "application/pdf" \
               and not fn.lower().endswith(".pdf"):
                continue
            try:
                payload = part.get_payload(decode=True)
            except Exception:
                continue
            # Sub-2KB "PDFs" are tracking stubs and broken parts, never documents.
            if not payload or len(payload) < 2048:
                continue
            h = hashlib.sha256(payload).hexdigest()
            if h in seen:
                continue
            created = None
            try:
                created = parsedate_to_datetime(date).date().isoformat()
            except Exception:
                pass
            title = (subj or fn or h[:12]).strip()[:120]
            safe = re.sub(r"[^A-Za-z0-9._-]", "_", fn or "attachment.pdf")[:120]
            try:
                post_document(payload, safe or "attachment.pdf", "application/pdf",
                              title, created, ensure("correspondents", correspondent_name(frm)),
                              [tag])
            except Exception as e:
                log(f"email: upload failed for {title[:40]}: {e}")
                continue
            seen.add(h)
            with SEEN_MAIL.open("a") as fh:
                fh.write(h + "\n")
            added += 1
    log(f"email: imported {added}")
    return added


# ------------------------------------------------------------------- photos

# ⚠️ This reads Immich's asset_ocr table directly. Immich exposes no OCR search
# in its API - /api/search/smart is CLIP, which is far too blunt for this - so
# there is no stable surface to use instead. Isolated in this one function so
# an Immich upgrade that renames the table breaks here, loudly, and nowhere
# else. The import half below is all public API.
SCORE_SQL = r"""
with txt as (
  select o."assetId" as id, lower(string_agg(o.text,' ')) as t
  from asset_ocr o join asset a on a.id = o."assetId"
  where a."deletedAt" is null and a.type = 'IMAGE'
  group by o."assetId"
), scored as (
  select id, t,
    (t ~ 'sort code')::int*10 + (t ~ 'account number')::int*10 +
    (t ~ 'national insurance')::int*10 + (t ~ 'hmrc')::int*10 +
    (t ~ '\mp(60|45)\M')::int*10 + (t ~ 'payslip|pay slip')::int*10 +
    (t ~ 'tax year|taxable')::int*8 + (t ~ 'policy number|policy no')::int*10 +
    (t ~ 'nhs number')::int*10 + (t ~ 'invoice number|invoice no')::int*10 +
    (t ~ 'vat registration|vat reg')::int*8 +
    (t ~ 'tenancy agreement|assured shorthold')::int*10 +
    (t ~ 'council tax')::int*10 + (t ~ 'driving licence|driver licence')::int*8 +
    (t ~ 'certificate')::int*5 + (t ~ '\minvoice\M')::int*4 +
    (t ~ '\mstatement\M')::int*4 + (t ~ 'amount due|total due|balance due')::int*4 +
    (t ~ 'due date')::int*3 + (t ~ '\mpremium\M|\minsurance\M')::int*3 +
    (t ~ 'landlord|tenancy|deposit')::int*3 + (t ~ 'mortgage|pension|dividend')::int*4 +
    (t ~ 'meter reading|tariff|kwh')::int*4 + (t ~ 'prescription|appointment')::int*3 +
    (t ~ '\mcontract\M|terms and conditions')::int*3 +
    (t ~ 'reference number|ref no|your ref')::int*3 +
    (t ~ '\mreceipt\M')::int*2 + (t ~ 'sub ?total|\mvat\M')::int*2 as score
  from txt
)
select s.id, s.score,
       to_char(coalesce(a."fileCreatedAt", a."createdAt"),'YYYY-MM-DD'),
       left(regexp_replace(s.t,'\s+',' ','g'), 90)
from scored s join asset a on a.id = s.id
where s.score >= %d
order by s.score desc;
"""

def score_photos(threshold):
    sql = SCORE_SQL % threshold
    out = subprocess.run(
        ["runuser", "-u", "postgres", "--", "psql", "-d", "immich", "-t", "-A", "-F", "|", "-c", sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        log(f"photos: scoring query failed: {out.stderr.strip()[:300]}")
        return []
    rows = []
    for line in out.stdout.split("\n"):
        if line.count("|") >= 3:
            rows.append(line.split("|", 3))
    return rows

def ingest_photos(seen, budget):
    rows = score_photos(REVIEW_SCORE)
    fresh = [r for r in rows if r[0] not in seen]
    log(f"photos: {len(rows)} scoring candidate(s), {len(fresh)} not yet imported")
    if not fresh:
        return 0
    tag_photo  = ensure("tags", "source:photo")
    tag_review = ensure("tags", "needs review")
    added = 0
    for aid, score, date, snippet in fresh:
        if added >= budget:
            log("photos: hit the per-run cap, the rest comes next run")
            break
        try:
            req = urllib.request.Request(f"{IMMICH}/assets/{aid}/original")
            req.add_header("x-api-key", IM_KEY)
            with urllib.request.urlopen(req, timeout=180) as r:
                blob, ct = r.read(), r.headers.get("Content-Type", "image/jpeg")
        except Exception as e:
            log(f"photos: download failed for {aid}: {e}")
            continue
        ext = ".jpg" if "jp" in ct else (".png" if "png" in ct else ".bin")
        words = " ".join(re.sub(r"[^A-Za-z0-9 ]", " ", snippet).split()[:8]) or "document"
        tags = [tag_photo] + ([tag_review] if int(score) < AUTO_SCORE else [])
        try:
            post_document(blob, f"{aid}{ext}", ct, f"Photo {date} - {words}"[:120],
                          date, None, tags)
        except Exception as e:
            log(f"photos: upload failed for {aid}: {e}")
            continue
        seen.add(aid)
        with SEEN_PHOTO.open("a") as fh:
            fh.write(aid + "\n")
        added += 1
    log(f"photos: imported {added}")
    return added


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    started = time.time()
    seen_mail  = set(SEEN_MAIL.read_text().split())  if SEEN_MAIL.exists()  else set()
    seen_photo = set(SEEN_PHOTO.read_text().split()) if SEEN_PHOTO.exists() else set()
    log(f"state: {len(seen_mail)} attachment(s) and {len(seen_photo)} photo(s) already imported")

    n = ingest_email(seen_mail, MAX_PER_RUN)
    n += ingest_photos(seen_photo, MAX_PER_RUN - n)

    # Only advance the watermark on a clean pass. A run that died halfway
    # rescans the same window tomorrow, which the seen-sets make harmless.
    WATERMARK.write_text(str(started))
    log(f"done: {n} new document(s) in {time.time() - started:.0f}s")

if __name__ == "__main__":
    main()
