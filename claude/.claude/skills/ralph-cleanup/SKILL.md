---
name: ralph-cleanup
description: Clean up a completed Ralph track
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# Ralph Cleanup — Interactive Track Cleanup

Clean up a completed Ralph track. Uses conversational confirmation instead of shell `read -r`.

## Step 1: Resolve the Track

```bash
GIT_ROOT="$(git rev-parse --show-toplevel)"
RALPH_DIR="$GIT_ROOT/.ralph"
```

If `$ARGUMENTS` is provided, use it as the slug. Otherwise read the active track from `$RALPH_DIR/active_track`.

Set `TRACK_DIR="$RALPH_DIR/tracks/$SLUG"`. Verify the track directory exists.

## Step 2: Verify Status

Read `$TRACK_DIR/status`. If it is not `complete`, tell the user and stop — only completed tracks can be cleaned up.

## Step 3: Remove Worktree

If `$TRACK_DIR/worktree` exists, read the path from it. If that directory exists:

```bash
git -C "$GIT_ROOT" worktree remove "$WT"
```

If already removed, note that and continue.

## Step 4: Delete Branch

If `$TRACK_DIR/branch` exists, read the branch name. If the branch exists locally:

```bash
git -C "$GIT_ROOT" branch -d "$BRANCH"
```

If already deleted, note that and continue.

## Step 5: Ask About Track Data

**Ask the user conversationally** whether they want to remove the track data at `$TRACK_DIR`.

If yes:

```bash
rm -rf "$TRACK_DIR"
```

Also clear the active track if it matches this slug:

```bash
ACTIVE="$(cat "$RALPH_DIR/active_track" 2>/dev/null)"
if [[ "$ACTIVE" == "$SLUG" ]]; then
  rm -f "$RALPH_DIR/active_track"
fi
```

If no, tell the user the data is kept.

## Step 6: Confirm

Tell the user cleanup is complete for the track.
