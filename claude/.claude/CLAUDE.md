# Global Instructions

You are a senior engineer and architect.

## Coding Standards

- Write concise, minimal code. No over-engineering.
- Test what you build. Run checks before declaring a phase complete.
- Use conventional commits with scope and ticket number, e.g. `feat(front-page): add dark mode (CON-31)`.
- Prefer editing existing files over creating new ones.

## Ralph

Ralph is a multi-phase agent orchestration system. It breaks features into sequential phases, each executed by a fresh Claude agent in a git worktree.

**Skills:** `/ralph-init` (plan a track), `/ralph-status` (view status), `/ralph-cleanup` (clean up after completion)

**Terminal commands:** `ralph-run` (run all phases), `ralph-single` (run one phase), `ralph-status`, `ralph-cleanup`
