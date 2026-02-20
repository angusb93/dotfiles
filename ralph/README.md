# Ralph — Manual

## What It Is

Ralph is a multi-phase agent orchestration system. You describe a feature, Ralph breaks it into sequential phases, then runs fresh Claude agents to execute each phase in a git worktree.

## Commands

### Planning (inside Claude Code)

```
/ralph-init <feature description>
```

Interactive planning session. Analyzes your codebase, discusses the approach with you, then writes a phased plan. Creates `.ralph/tracks/<slug>/` in your repo.

Example: `/ralph-init add dark mode support`

### Execution (from terminal)

```bash
ralph-run [track-slug] [--model MODEL] [--budget N]   # run all phases sequentially
ralph-single [track-slug] [--model MODEL] [--budget N] # run one phase at a time
```

Both create a git worktree and branch (`ralph/<slug>`), then spawn headless `claude -p` agents. Defaults: `--model sonnet --budget 5.00`.

`ralph-run` loops through every remaining phase. `ralph-single` runs just the next one and stops — useful if you want to review between phases.

### Status

```
/ralph-status [track-slug]    # inside Claude Code
ralph-status [track-slug]     # from terminal
```

Shows track status, current phase, and phase history. Omit the slug to show the active track (or all tracks).

### Cleanup (after PR merged)

```
/ralph-cleanup [track-slug]   # inside Claude Code (preferred — interactive confirmation)
ralph-cleanup [track-slug]    # from terminal
```

Removes the worktree, deletes the branch, and optionally removes track data. Only works on tracks with status `complete`.

## Typical Workflow

1. **Plan:** `/ralph-init add user authentication` — discuss and approve the plan
2. **Run:** `ralph-run` from terminal — agents execute each phase, committing and pushing
3. **Monitor:** `/ralph-status` or `ralph-status` to check progress
4. **Review:** Agents open a draft PR on phase 1 and mark it ready on the final phase
5. **Merge:** Review and merge the PR
6. **Clean up:** `/ralph-cleanup` to remove worktree, branch, and track data

## File Structure

```
.ralph/
  .gitignore          # ignores everything (track data stays local)
  active_track        # current track slug
  tracks/
    <slug>/
      status          # planning → planned → in_progress → complete
      current_phase   # integer
      plan.md         # the phased plan
      state.md        # agent-appended phase history
      branch          # git branch name
      worktree        # worktree path
      logs/
        phase-1.log   # agent output per phase
```

## Commit Convention

When working on a Ralph track, commits are prefixed: `ralph(<slug>): <message>`
