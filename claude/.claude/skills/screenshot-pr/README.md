# screenshot-pr

> Capture before/after screenshots of UI changes on the current branch and post them to the open GitHub PR as a comment with visual diffs.

## Author

George Walker — @george / georgewalker@improbable.io

## Overview

Agentic visual-diff for PRs. You run it on a branch with an open PR that touches UI, and it:

1. Inspects the diff and classifies which files actually affect the UI.
2. Traces changed components to the routes/URLs where they render (route conventions, Storybook stories, or import-graph tracing).
3. Starts your dev server, drives Playwright (Chromium) to capture the **after** state, checks out the base ref to capture the **before**, and diffs the images.
4. Hosts the images (orphan branch for public repos, release assets for private repos) and posts/updates a single PR comment with a before/after/diff table.

There's no config file mapping components to URLs — it figures targets out and shows you the plan before burning time capturing. Best for frontend PRs where a reviewer wants to *see* the change.

## Dependencies

- **Node.js** + **npm** — to run the capture helper.
- **Playwright** (`^1.50.0`) + Chromium — the capture engine. First run bootstraps it:
  ```bash
  npm i --prefix <skill-dir>/scripts
  npx -y -p playwright@latest playwright install chromium
  ```
- **`gh` CLI**, authenticated — PR lookup, repo visibility, posting/patching comments, and (private repos) hosting images via `gh release`.
- **`git`** with `worktree` support — pushes the screenshot orphan branch without disturbing your working tree (public repos).
- **`odiff-bin`** (via `npx -y`) — perceptual image diff. Falls back to `pixelmatch-cli`.
- A runnable **dev server** in the project (`dev` / `start` / `serve` / `preview` script).

Everything beyond Playwright is fetched on demand with `npx -y` — nothing is installed globally.

## Usage

```bash
cp -r screenshot-pr ~/.claude/skills/
# first run on a machine, install the capture deps:
npm i --prefix ~/.claude/skills/screenshot-pr/scripts
npx -y -p playwright@latest playwright install chromium
```

Then, on a branch with an open PR, ask Claude to *"screenshot the PR"* (or "show visual changes", "add screenshots to the PR", "diff the UI").

> The `capture.mjs` helper imports `playwright` as an ESM module, so it must resolve from a `node_modules` next to the script — `npx -p playwright node capture.mjs` does **not** work. Always run the `npm i --prefix .../scripts` bootstrap first.

## Caveats

- **Expensive** — installs browsers, starts servers, checks out refs. Run it manually, not on every commit / as a hook.
- **Public vs private repos host images differently.** Public → orphan branch + `raw.githubusercontent.com`; private → GitHub release assets on the `github.com` domain (raw URLs don't render inline for private repos). The skill detects this, but it's the most common gotcha.
- **Honours push-hours rules** — if your `~/.claude/CLAUDE.md` defines push hours, it confirms before pushing/publishing outside them.
- Dynamic regions (live counters, relative timestamps, clocks) inflate diffs — mask them with `--mask` or expect some noise.
- `node_modules/` is intentionally **not** committed here — run the bootstrap to populate it.
- Shared as-is — test on a low-stakes PR first.
