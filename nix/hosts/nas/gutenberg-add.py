"""Pull a book out of the Gutenberg ZIM on tank and drop it in the Calibre-Web inbox.

The ZIM holds a real .epub per book, but kiwix-serve's OPDS catalogue advertises
the three ZIM *files* rather than their contents, so KOReader cannot browse it
directly. This is the bridge.

Two indexes, and you need both:

  /suggest  is a TITLE index. Case-sensitive, and matches from the START of the
            title. "Crime and Pun" hits; "crime and pun" does not, and neither
            does "Punishment" on its own.
  /search   is a FULL-TEXT index over book contents, relevance-ranked. It
            buries famous novels: "crime and punishment" returns a thousand
            criminology texts and not Dostoevsky, while "Raskolnikov" finds him
            immediately.

So: smart-case the query and try the title index first, then append full-text
hits underneath. Title matches are what you almost always want, which is why
they are listed first.
"""

import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request

KIWIX = "http://127.0.0.1:8090"
BOOK = "gutenberg"
INBOX = "@INBOX@"

# Words English titles leave lowercase. Capitalising these breaks the
# prefix match: "Crime And Punishment" does not match "Crime and Punishment".
SMALL = {
    "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "nor",
    "of", "on", "or", "the", "to", "with", "over", "under",
}


def fetch(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "gutenberg-add"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def smart_title(text):
    """Capitalise like a book title: first word always, small words never."""
    words = text.split()
    out = []
    for i, w in enumerate(words):
        out.append(w.capitalize() if (i == 0 or w.lower() not in SMALL) else w.lower())
    return " ".join(out)


def normalise(name):
    """Make one canonical, DECODED entry name out of either index.

    ⚠ The two endpoints disagree on encoding: /suggest returns paths with
    literal spaces and HTML entities ("Jane Austen&apos;s"), /search returns
    them percent-encoded. Decoding both here means dedup works across the two
    and there is exactly one place that re-encodes, in entry_url().
    """
    return html.unescape(urllib.parse.unquote(re.sub(r"\.html$", "", name)))


def entry_url(entry, suffix):
    """The only place an entry name gets percent-encoded."""
    return f"{KIWIX}/content/{BOOK}/{urllib.parse.quote(entry)}{suffix}"


def suggest(term):
    """Title-index hits, in order."""
    url = f"{KIWIX}/suggest?content={BOOK}&term={urllib.parse.quote_plus(term)}"
    try:
        data = json.loads(fetch(url, 30))
    except Exception:
        return []
    out = []
    for item in data:
        if item.get("kind") == "pattern":
            continue
        path = item.get("path") or ""
        # Every book has a matching _cover page; it is not the book.
        if not path or "_cover." in path:
            continue
        out.append(normalise(path))
    return out


def fulltext(term):
    """Full-text hits, in relevance order."""
    url = (f"{KIWIX}/search?books.name={BOOK}"
           f"&pattern={urllib.parse.quote_plus(term)}&pageLength=20")
    try:
        html = fetch(url, 40).decode("utf-8", "replace")
    except Exception:
        return []
    hits = re.findall(r'href="/content/' + BOOK + r'/([^"]+)\.html"', html)
    return [normalise(h) for h in hits if "_cover." not in h]


def pretty(entry):
    """'Crime and Punishment.2554' -> 'Crime and Punishment  (#2554)'."""
    m = re.match(r"^(.*)\.(\d+)$", entry)
    if m:
        return f"{m.group(1)}  (#{m.group(2)})"
    return entry


def main():
    if len(sys.argv) < 2:
        print("usage: gutenberg-add <search terms>", file=sys.stderr)
        return 2

    query = " ".join(sys.argv[1:])

    # Checked up front and named plainly. Without this, an unwritable inbox
    # surfaces as a failure to create the output file, which reads as "no epub
    # in the ZIM" - the wrong cause entirely. Group membership only takes
    # effect on a new login.
    if not os.access(INBOX, os.W_OK):
        print(f"Cannot write to {INBOX}.", file=sys.stderr)
        print("If you are not in the 'calibre-web' group, log out and back in;",
              file=sys.stderr)
        print("if you are, this shell predates the group change.", file=sys.stderr)
        return 1

    # The title index matches from the START of the title, so "war of the
    # worlds" misses "The War of the Worlds" entirely. Try the leading article
    # too - by far the most common way a remembered title is short of the real
    # one. Each variant is one cheap request against a local index.
    titled = smart_title(query)
    variants = [titled]
    if titled != query:
        variants.append(query)
    if not re.match(r"(?i)^(the|a|an)\b", query):
        variants += [f"The {titled}", f"A {titled}", f"An {titled}"]

    title_hits = []
    for v in variants:
        title_hits += suggest(v)

    ordered = []
    seen = set()
    for entry in title_hits:
        if entry not in seen:
            seen.add(entry)
            ordered.append(entry)
    n_title = len(ordered)
    for entry in fulltext(query):
        if entry not in seen:
            seen.add(entry)
            ordered.append(entry)

    if not ordered:
        print(f"No matches for: {query}", file=sys.stderr)
        print("The title index matches from the start of the title, so try the "
              "opening words, or a distinctive word for a full-text search.",
              file=sys.stderr)
        return 1

    ordered = ordered[:15]
    print("Matches:")
    for i, entry in enumerate(ordered, 1):
        mark = "  " if i <= n_title else " ~"
        print(f" {mark}{i:>2}) {pretty(entry)}")
    if n_title and n_title < len(ordered):
        print("\n   (~ = full-text match on the contents, not the title)")

    try:
        choice = input(f"\nWhich one? [1-{len(ordered)}, or q] ").strip()
    except EOFError:
        choice = "q"
    if choice.lower() in ("q", ""):
        print("Nothing added.")
        return 0
    if not choice.isdigit() or not 1 <= int(choice) <= len(ordered):
        print(f"Not a valid choice: {choice}", file=sys.stderr)
        return 1

    entry = ordered[int(choice) - 1]
    name = re.sub(r"[^A-Za-z0-9.-]+", "_", entry)
    out = os.path.join(INBOX, f"{name}.epub")

    try:
        data = fetch(entry_url(entry, ".epub"), 180)
    except Exception as e:
        print(f"Could not fetch it: {e}", file=sys.stderr)
        print("Some ZIM entries ship only HTML, with no .epub.", file=sys.stderr)
        return 1

    if not data[:2] == b"PK":
        print("That entry has no real .epub in the ZIM (got non-zip data).",
              file=sys.stderr)
        return 1

    with open(out, "wb") as fh:
        fh.write(data)

    # Apparent size, not du: on ZFS the blocks are not allocated yet when this
    # runs, so du reports a freshly written 700 KB epub as "1.0K".
    print(f"\nDropped {len(data) // 1024} KB in the inbox: {pretty(entry)}")
    print("Calibre-Web files it within ~10s - check http://morty:8083")
    return 0


if __name__ == "__main__":
    sys.exit(main())
