---
name: ralph-init
description: Plan a new Ralph track interactively
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - Edit
---

# Ralph Init — Interactive Track Planning

You are planning a Ralph track. The user provided a feature description as `$ARGUMENTS`.

## Step 1: Compute Paths

Derive these values using Bash:

```bash
GIT_ROOT="$(git rev-parse --show-toplevel)"
```

**Slugify `$ARGUMENTS`:** lowercase, replace non-alphanumeric with `-`, collapse consecutive hyphens, trim leading/trailing hyphens.

Example: "Add Dark Mode Support" → `add-dark-mode-support`

```
SLUG="<slugified>"
RALPH_DIR="$GIT_ROOT/.ralph"
TRACK_DIR="$RALPH_DIR/tracks/$SLUG"
```

## Step 2: Check for Existing Track

If `$TRACK_DIR` already exists, tell the user the track already exists and stop.

## Step 3: Initialize Directory Structure

```bash
mkdir -p "$TRACK_DIR/logs"

# Create .gitignore if missing
if [[ ! -f "$RALPH_DIR/.gitignore" ]]; then
  printf '*\n!.gitignore\n' > "$RALPH_DIR/.gitignore"
fi

echo "planning" > "$TRACK_DIR/status"
echo "0" > "$TRACK_DIR/current_phase"
```

Write `$TRACK_DIR/state.md`:

```markdown
# Track State: <slug>

Phase history will be appended below by agents.
```

## Step 4: Analyze & Discuss

Now analyze the codebase and discuss the plan with the user:

- Read key project files (package.json, Cargo.toml, Makefile, etc.) to understand the stack
- Explore relevant source code
- Propose an approach and iterate with the user
- Break the feature into 3–8 small sequential phases

## Step 5: Write plan.md

Once the user is happy, write `$TRACK_DIR/plan.md` using this exact format:

```markdown
# Track: <name>

## Description

<1-2 sentences describing the feature/task>

## Phases

### Phase 1: <title>

**Description:** <what to do in this phase>
**Files:** <expected files to touch>
**Checks:** <phase-specific validation commands>

### Phase 2: <title>

**Description:** <what to do>
**Files:** <expected files>
**Checks:** <validation commands>

...

## Quality Gates

- <command 1, e.g. "pnpm build">
- <command 2, e.g. "pnpm test">
- <command 3, e.g. "pnpm lint">
```

### Phase Design Guidelines

- Phase 1 sets up the foundation (config, types, scaffolding)
- Middle phases implement the feature incrementally
- Final phase runs all quality gates and polishes. This should include things like linting, formatting, building and running type checks as well as other things like testing where applicable
- Each phase must produce a working (if incomplete) codebase
- Keep phases small enough that an agent can finish in one session
- Include specific file paths where possible
- Phase checks should be fast, deterministic commands

## Step 6: Finalize

After writing plan.md:

```bash
echo "planned" > "$TRACK_DIR/status"
echo "$SLUG" > "$RALPH_DIR/active_track"
```

Count the phases and print a summary:

```
Track '<slug>' planned with N phases.
Active track set to: <slug>

Next steps:
  ralph-run             # run all phases
  ralph-single          # run one phase at a time
  /ralph-status         # view the plan
```
