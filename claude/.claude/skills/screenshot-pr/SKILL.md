---
name: screenshot-pr
description: Capture before/after screenshots of UI changes on the current branch and attach them to the open GitHub PR with visual diffs. Use when the user asks to "screenshot the PR", "screenshot this PR", "show visual changes", "capture UI diff", "add screenshots to the PR", "diff the UI", or wants a visual review comment posted on a PR for frontend changes. Agentic — figures out what changed, where it renders, and what to capture without requiring a config file.
---

# Screenshot PR

Capture before/after screenshots of UI changes on the current branch and post them to the open GitHub PR as a comment with visual diffs.

You are agentic about this — there is no config file mapping components to URLs. You inspect the diff, trace components to their render locations, start the dev server, drive Playwright, diff the images, and publish the result.

## When to run

Invoked manually by the user for a branch with an open PR that contains UI changes. Do NOT run on every commit or as a hook — it's expensive (installs browsers, starts servers, checks out refs).

## Decision tree at the top

1. Are we in a git repo with an open PR? → check, or stop.
2. Are there UI changes to screenshot? → classify the diff, or stop and say so.
3. Can I map changed files to URLs? → try several strategies, ask the user if stuck.
4. Is there a dev server command? → find and run it.
5. Capture → checkout base → capture → checkout back → diff → publish.

Be chatty with the user about what targets you picked BEFORE you burn time capturing. Don't silently screenshot the wrong things for 6 components.

---

## Step 1 — Preflight

```bash
git rev-parse --is-inside-work-tree
gh pr view --json number,headRefName,baseRefName,url
git status --porcelain    # warn user if dirty — we'll need to stash
```

If there is no open PR, tell the user to push and open one first (or ask if they want screenshots without a PR — we can save them locally and skip publish).

Fetch the base ref so we can check it out later:
```bash
BASE=$(gh pr view --json baseRefName -q .baseRefName)
git fetch origin "$BASE"
```

## Step 2 — What changed?

```bash
git diff --name-only "origin/$BASE...HEAD"
```

Classify each file. Use judgement:

| Category | Examples | Action |
|---|---|---|
| Direct UI | `.tsx .jsx .vue .svelte .astro .html` | capture |
| Styles | `.css .scss .sass .module.*` | capture routes that use the component, OR representative pages if it's global |
| Theme/tokens | `tailwind.config.*`, `theme.ts`, design-token files | capture 2–3 representative routes |
| UI-adjacent | hooks/utils imported by UI | capture if you can trace the effect; skip if risky |
| Config / backend / docs / tests | `package.json`, `.md`, `*.test.*`, server code | skip |

If the UI file count is zero, stop: "No UI-affecting changes detected — nothing to screenshot."

If there are more than ~10 UI targets, show the user the list and ask which to capture. Don't silently do 30 screenshots.

## Step 3 — Map files to URLs

For each UI file, find where it renders. Use whichever technique fits — in this order:

**A. It IS a page/route.** Map directly from the path:
- Next.js app router: `app/foo/bar/page.tsx` → `/foo/bar`. `app/page.tsx` → `/`. Ignore `layout.tsx`, `loading.tsx`, `error.tsx` (screenshot the pages they wrap instead).
- Next.js pages router: `pages/foo.tsx` → `/foo`, `pages/index.tsx` → `/`. Ignore `_app.tsx`, `_document.tsx`.
- Remix / React Router v7: `app/routes/foo.tsx` → `/foo`, `app/routes/foo.bar.tsx` → `/foo/bar`, `app/routes/_index.tsx` → `/`.
- SvelteKit: `src/routes/foo/+page.svelte` → `/foo`.
- Astro: `src/pages/foo.astro` → `/foo`.
- Static HTML: the file itself.

**B. Component — find its stories.** If `Foo.stories.{ts,tsx,js,jsx,mdx}` exists as a sibling, the Storybook server has a URL per story. If Storybook is running (`pnpm storybook`, `npm run storybook`), prefer this — cleanest isolation.

**C. Component — trace to a route.** Grep for importers and walk up:
```bash
git grep -l "from ['\"].*ComponentName['\"]"
```
Repeat on each importer until you hit a page file, then apply rule A. Cap the trace at ~3 hops to avoid getting lost in the forest.

**D. Global styles / theme.** Screenshot 2–3 representative routes — homepage plus one or two information-dense pages.

**E. Stuck.** Ask the user: *"I couldn't find where `src/components/FancyModal.tsx` renders — can you give me a URL, or a user action that opens it?"*

Build a plan and show it:
```
Plan:
  • src/components/Button.tsx    → /buttons-demo, /settings          (desktop, mobile)
  • src/app/pricing/page.tsx     → /pricing                          (desktop, mobile)
  • src/styles/theme.css         → /, /dashboard                     (desktop only)

Proceed? (y/n)
```

Wait for confirmation unless the user said "just do it".

## Step 4 — Start the dev server

Read `package.json` scripts. Prefer, in order: `dev`, `start`, `serve`, `preview`. Detect the package manager (`pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; else npm).

Check the project's `dev` script for an explicit port (`next dev -p 3001`) before falling back to the common list (3000, 5173, 4200, 8080, 8000).

⚠️ **Another project may already squat the port.** If you reuse "whatever answers on :3000" you can silently screenshot the wrong app (a different repo's dev server). Before reusing a running server, confirm it's *this* project — e.g. `curl -s localhost:$PORT/ | grep -q '<an app-specific string>'` (a title, a known route label, a component marker). If it's a different app, start your own on a free port (`-p 3001`) and use that. After your server is up, also confirm it serves *your branch* (grep the page for a string unique to the change) — dev servers can serve a stale compile.

**A 200 on the HTML is NOT proof the server is healthy.** A long-running dev server with a stale build cache can serve the page fine while 404-ing its own CSS — captures then come out as unstyled raw HTML. Health-check the stylesheet, not just the page:

```bash
health_check() {
  curl -sf -o /dev/null "http://localhost:$PORT/" || return 1
  CSS=$(curl -s "http://localhost:$PORT/" | grep -oE 'href="[^"]*\.css[^"]*"' | head -1 | sed 's/href="//;s/"$//')
  [ -z "$CSS" ] && return 0   # no external stylesheet (inlined) — accept
  [ "$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT$CSS")" = "200" ]
}
```

If something is already serving and passes `health_check`, reuse it. If it serves HTML but fails the CSS check, it's stale — kill it and restart with the same command (tell the user you did).

Otherwise run the dev command in the background:
```bash
(cd "$(git rev-parse --show-toplevel)" && pnpm dev) > /tmp/screenshot-pr-server.log 2>&1 &
echo $! > /tmp/screenshot-pr-server.pid
```

Poll for up to 45s until `health_check` passes (parse the port from the server log, or try the common list). If it never comes up, read the log and tell the user.

## Step 5 — Ensure Playwright is available

The `capture.mjs` helper lives at `~/.claude/skills/screenshot-pr/scripts/` and imports
`playwright` as an ESM module — it must resolve from a `node_modules` next to the script.
**`npx -y -p playwright node capture.mjs` does NOT work** (ESM imports don't resolve from
the npx cache). Bootstrap once per machine, idempotent and fast when already installed:

```bash
SCRIPTS=~/.claude/skills/screenshot-pr/scripts
npm i --prefix "$SCRIPTS" --no-audit --no-fund   # installs deps from scripts/package.json
npx -y -p playwright@latest playwright install chromium   # browser binary (cached globally)
```

After that, `node "$SCRIPTS/capture.mjs"` works from any cwd.

## Step 6 — Capture the "after" (current branch)

```bash
ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$ROOT/.pr-screenshots"/{before,after,diff}

# Warm every target route first — dev servers (Next, Vite) compile per-route on
# first hit, and the first browser load can race the CSS even at networkidle.
for each route: curl -s -o /dev/null "http://localhost:$PORT$ROUTE"

for each target:
  node ~/.claude/skills/screenshot-pr/scripts/capture.mjs \
    --url "http://localhost:$PORT$ROUTE" \
    --out "$ROOT/.pr-screenshots/after/<slug>-<viewport>.png" \
    --viewport "1280x800"
```

Slug = `<filename>-<route>` with non-alphanumeric chars replaced by `-`. Viewports default to desktop (1280×800) and mobile (375×812). Skip mobile for theme-only runs unless the user asks.

**Sanity-check the first capture** (Read the PNG) before burning time on the rest — verify it's styled and shows the right page. capture.mjs also self-checks for missing styles and reloads once, but a stale server will defeat that.

**Mask known-dynamic regions.** Live counters (sync status, event counts), relative-time defaults (`now + N min` in date inputs), and clocks inflate every diff. Pass `--mask "selector1,selector2"` for regions you can identify up front; otherwise note the noise in the summary. (A reliable mask for a live status pill is often `header span[title]`.)

**Capture interactive states for behavioral changes.** When the change is mostly *behavior* — a collapsible section, a menu that opens, a hover/active style, a responsive breakpoint — a static before/after diffs near 0% and undersells it. Drive the state with `capture.mjs --click '<selector>'` (e.g. `button[aria-label="Open menu"]`) and post it as an **after-only "🆕 new" panel** in the comment, since the state often doesn't exist on base at all. For responsive nav, the mobile (375px) viewport with the menu open is usually the most telling shot.

## Step 7 — Capture the "before" (base branch)

⚠️ **Do NOT `git stash push -u` blindly** — `-u` (include-untracked) will sweep up the `.pr-screenshots/after/` images you just captured (they're untracked), removing them mid-run. Two safe options:
- **Preferred:** if the PR branch has no *tracked* working-tree changes (`git status --porcelain | grep -v '^??'` is empty — the usual case on a committed PR branch), skip the stash entirely. `git checkout origin/$BASE --detach` proceeds fine; untracked `.pr-screenshots/` and gitignored files (`.env.local`) are non-conflicting and survive the checkout. (Capturing into a path *outside* the repo, e.g. `/tmp`, sidesteps this entirely.)
- If there *are* tracked changes, stash only those: `git stash push -m … -- <tracked paths>` (no `-u`), never the screenshots dir.

```bash
# only if tracked changes exist:
git stash push -m "screenshot-pr-$(date +%s)" -- <tracked-paths> || STASHED=no
git checkout "origin/$BASE" --detach
```

If the dev server reads a gitignored env (e.g. `.env.local` pointing at a deployed indexer), confirm it's gitignored (`git check-ignore`) so the checkout leaves it in place — the "before" capture then hits the same backend as "after".

Dev servers with HMR (`next dev`, `vite`) pick up the checkout automatically and recompile — no restart needed in the common case. Strategy:
1. After checkout, poll `health_check` (step 4) until the recompile settles — usually a few seconds — then re-warm the target routes with curl.
2. If routes 404 or the build is stale, stop the server, reinstall if `package-lock` / `pnpm-lock.yaml` differ between the refs, restart, wait.
3. If a route doesn't exist on base (new page), record "new" for that target and skip its before capture.

Capture each target into `.pr-screenshots/before/`.

Return to the PR branch:
```bash
git checkout -
[ "$STASHED" != "no" ] && git stash pop
```

## Step 8 — Diff

For each (before, after) pair:
```bash
npx -y odiff-bin \
  ".pr-screenshots/before/<slug>.png" \
  ".pr-screenshots/after/<slug>.png" \
  ".pr-screenshots/diff/<slug>.png" \
  --threshold=0.1 --antialiasing || true
```

`odiff-bin` exits non-zero when images differ — that's fine, capture its stdout. It prints a line like `Different pixels: 1234 (1.23%)` which you can parse.

Record per target: `unchanged` (<0.05%), `changed (X%)`, or `new`.

## Step 9 — Publish screenshots to an orphan branch

**Local-only mode:** if the user asked to keep screenshots local (or there's no PR / no remote), stop here — print the per-target diff table with local paths to `before/`, `after/`, `diff/`, leave `.pr-screenshots/` in place, and offer to run the publish steps later. Skip steps 9–10 entirely.

**FIRST — check repo visibility. This decides the hosting method:**
```bash
PR=$(gh pr view --json number -q .number)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PRIVATE=$(gh repo view --json isPrivate -q .isPrivate)   # "true" | "false"
```

⚠️ **`raw.githubusercontent.com` only renders inline for PUBLIC repos.** For a **private** repo it is a *separate domain* the viewer's browser has no auth cookies for, so the images 404 and show broken — even for members with full access (GitHub leaves the `<img src>` un-proxied; it is NOT camo'd, so the browser fetches `raw` directly and fails). Do not "test" this with `curl -H "Authorization: token …"` — a token in a header returns 200 while the cookie-based browser request a viewer makes returns 404. The two are not equivalent.

So:
- **Public repo → orphan branch + `raw.githubusercontent.com`** (Path A below).
- **Private repo → GitHub release assets** served from the **github.com** domain (Path B below). Because the comment and the asset are both on `github.com`, the viewer's existing session cookies authenticate the request, so it renders. (This is also why `github.com/<owner>/<repo>/releases/download/...` works where `raw.githubusercontent.com/...` does not.)

### Path A — public repo (orphan branch)

```bash
STAMP=$(date +%Y%m%d-%H%M%S)
SHOT_BRANCH="screenshots/pr-$PR-$STAMP"
TMPWT=$(mktemp -d)                          # temp worktree, doesn't disturb the working copy
git worktree add -q --detach "$TMPWT"
(
  cd "$TMPWT"
  git checkout --orphan "$SHOT_BRANCH"
  git rm -rf . 2>/dev/null || true
  cp -r "$ROOT/.pr-screenshots/"* .
  git add -A
  git -c commit.gpgsign=false commit -m "Screenshots for PR #$PR ($STAMP)"
  git push origin "$SHOT_BRANCH"
)
git worktree remove -f "$TMPWT"
# Raw URL per image:  https://raw.githubusercontent.com/$REPO/$SHOT_BRANCH/after/<slug>.png
```

### Path B — private repo (release assets)

Asset names must be **unique across the whole release**, so flatten `before/after/diff` into the filename. `gh release upload` is fully supported (no reverse-engineering, unlike `user-attachments`).

```bash
TAG="pr$PR-ui-screenshots"
mkdir -p /tmp/shot-upload
for cat in before after diff; do
  for f in "$ROOT/.pr-screenshots/$cat"/*.png; do
    [ -e "$f" ] && cp "$f" "/tmp/shot-upload/${cat}-$(basename "$f")"
  done
done
gh release create "$TAG" --prerelease --target "$(git rev-parse HEAD)" \
  --title "PR #$PR UI screenshots (auto)" \
  --notes "Auto-generated screenshots for PR #$PR. Safe to delete after review."
gh release upload "$TAG" /tmp/shot-upload/*.png --clobber   # --clobber lets you re-run / update
# URL per image:  https://github.com/$REPO/releases/download/$TAG/<cat>-<slug>.png
```
Tell the user the prerelease + tag are throwaway and offer to delete them (`gh release delete "$TAG" --cleanup-tag --yes`) once they've reviewed. To **update** assets on a re-run, re-upload with `--clobber` (the comment URLs stay valid); note GitHub's CDN may need a hard refresh to show the new bytes.

**Push hours check:** if the user's `~/.claude/CLAUDE.md` defines a push-hours rule (currently active or not), confirm with the user before pushing/publishing outside those hours. Run `date` to check.

**Verify it actually renders:** after posting, fetch the comment's rendered HTML (`gh api repos/$REPO/issues/comments/<id> -H "Accept: application/vnd.github.html+json" --jq .body_html`) and confirm the `<img src>` is the expected host (github.com release URL for private, raw for public) and not rewritten to a broken camo URL. If the user reports broken images on a private repo, you almost certainly used Path A — switch to Path B.

## Step 10 — Post (or update) the PR comment

Build a markdown comment. Use an HTML marker so we can find and update it next time:

```markdown
## Visual changes — PR #123

<!-- screenshot-pr:marker -->

_Base: `main@abc1234` · Head: `feature/x@def5678` · Captured 2026-04-19 14:32 UTC_

### `src/components/Button.tsx` — 1.2% changed

| Before | After | Diff |
|---|---|---|
| <img src="https://raw.../before/button-desktop.png" width="320"> | <img src="https://raw.../after/button-desktop.png" width="320"> | <img src="https://raw.../diff/button-desktop.png" width="320"> |

### `src/app/pricing/page.tsx` — 0.0% (unchanged) ✅

### `src/app/new-page/page.tsx` — 🆕 new

| After |
|---|
| <img src="https://raw.../after/new-page-desktop.png" width="480"> |
```

Tips:
- Group by file, show each viewport as a sub-row.
- Keep unchanged targets collapsed or just listed by name — don't spam big images for no-op diffs.
- Use `<img width="320">` so three images fit in a row without horizontal scroll.

Post / update:
```bash
# check for existing comment
EXISTING=$(gh api "repos/$REPO/issues/$PR/comments" \
  --jq '[.[] | select(.body | contains("<!-- screenshot-pr:marker -->"))][0].id')

if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
  gh api "repos/$REPO/issues/comments/$EXISTING" -X PATCH --field body=@/tmp/pr-screenshots-comment.md
else
  gh pr comment "$PR" --body-file /tmp/pr-screenshots-comment.md
fi
```

## Step 11 — Clean up

- Kill the dev server you started: `kill $(cat /tmp/screenshot-pr-server.pid) 2>/dev/null` (or `lsof -ti:$PORT | xargs kill`).
- Remove `.pr-screenshots/` from the working tree (don't commit it) and any `/tmp/shot-upload`, `/tmp/pr-screenshots-comment.md`.
- Leave `.gitignore` alone. Leave the hosting artifact in place so reviewers can see the images: the orphan branch (Path A) or the prerelease + tag (Path B). Tell the user how to delete it when done.
- Print a summary: comment URL, hosting artifact (branch or release tag), per-target diff %.

---

## Etiquette

- **Never commit to the PR branch.**
- **Never force-push.**
- **Never modify `.gitignore` or `package.json`.**
- **Never install deps globally** — `npx -y` everything.
- **Always show the plan before capturing** if there are >3 targets.
- **Stop and ask** rather than guessing when you can't map a file.

## When things go wrong

| Symptom | Do this |
|---|---|
| Images show broken in the comment on a **private** repo | You used `raw.githubusercontent.com` (Path A) — it doesn't render for private repos. Re-host via release assets (Step 9 Path B) on the github.com domain and update the comment |
| Reused server serves a 200 but the wrong app | A different project may squat the port (e.g. another Next dev server on :3000). `health_check` only proves "something styled is up" — also grep the page for an app-specific string before reusing; otherwise start your own on a free port |
| Diff % is tiny but the change is real | The change is behavioral/interactive (collapsible section, menu toggle, hover) — a static before/after won't show it. Capture the interactive state with `--click` as an after-only "🆕 new" panel (see Step 6) |
| Dev server won't start | Tail the log, show the user, ask for the command |
| Captures come out as unstyled raw HTML | Server is serving 200 HTML but its CSS 404s (stale build cache) or the route was cold-compiling. Run the step-4 `health_check`; restart the server if it fails, warm routes with curl, re-capture |
| `capture.mjs` fails with `ERR_MODULE_NOT_FOUND: playwright` | Run the step-5 bootstrap (`npm i --prefix ~/.claude/skills/screenshot-pr/scripts`) — npx does not make playwright resolvable to the script |
| Port detection fails | Ask the user for the port |
| Route 404 on one branch | Mark as "new" or "removed", continue others |
| Dynamic content (timestamps, carousels) causing constant diff | Note in the comment: "⚠ animated — diff may be spurious" |
| Base branch has different deps (lockfile changed) | Reinstall before capturing base, restart server |
| odiff-bin not available on this platform | Fall back to `npx -y pixelmatch-cli` or skip diff and just post before/after |
| User has no GitHub remote configured | Save screenshots locally, print paths, skip publish |

## Tools used

- **Playwright** (chromium) — the capture engine. Headless, deterministic, disables animations in init script.
- **odiff-bin** — fast perceptual image diff with a CLI. Falls back to `pixelmatch` if unavailable.
- **gh** — for PR lookup, repo visibility (`isPrivate`), posting/patching comments, and (private repos) hosting images via `gh release create/upload`.
- **git worktree** — for pushing the orphan branch (public repos) without disturbing the working tree.
- **npx -y** — everything installed on demand, nothing lingers globally.
