---
name: ship
description: Review committed changes locally with fresh eyes then CodeRabbit, open or update a PR, watch CI and merge conflicts until green, then drive CodeRabbit and Copilot review comments on the PR to resolution. Use when the user asks to ship, ship it, push safely, babysit a PR, handle review comments, or invokes /ship.
---

# ship

Validate the current branch's changes, get them onto a PR, and babysit that PR until CI is green and every CodeRabbit and Copilot review thread is resolved.
You drive everything yourself with `git` and `gh`.

Never merge the PR; merging is the user's call.
If the user wants the PR driven all the way into the default branch, that is the `ship-merge` skill, which runs this whole pipeline and then keeps going.

## Token discipline

This skill runs long waits against chatty APIs, and every byte of output you pull into your context is paid for again on every subsequent call.
Follow these rules throughout:

- Never poll with repeated tool calls.
  Do all waiting inside a single Bash call that loops with `sleep` and prints one final status line.
- Never pull raw JSON or full logs into your context.
  Filter every `gh` call with `--jq` down to the exact fields you need.
- Send bulky reading (the diff, failing CI logs) to a subagent and keep only its conclusions.

Work through the phases in order.
Phases 3 and 4 loop: a push made while handling review comments sends you back to the CI watch before re-requesting review.

## Phase 0: Preconditions

- The work must be committed.
  If there are uncommitted changes that belong to the task, commit them with a conventional commit message.
  Preserve unrelated pre-existing changes; never sweep them into your commits.
- You must be on a feature branch.
  If on the default branch, create a feature branch first and move the work there.
- `gh auth status` must succeed.
- Resolve the default branch from the remote rather than assuming `main` or `master`:

  ```sh
  gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
  ```

  Use that name wherever `<default-branch>` appears below.
  Do not trust `origin/HEAD`; it is frequently stale and can point at a branch the repo has stopped using.

Then rebase onto the current default branch, before the review and before anything is pushed.
This is what makes the branch mergeable, and it means the phase 1 reviews and CI both run against the base the PR will actually merge into:

```sh
git fetch origin
git rebase origin/<default-branch>
```

- Resolve any conflicts with the smallest correct resolution, then `git rebase --continue`.
- If a conflict is beyond mechanical resolution, or resolving it would mean guessing at someone else's intent, run `git rebase --abort` and bring it to the user rather than inventing a merge you cannot justify.
- The rebase rewrites history, so if the branch was already pushed, every push from here on uses `git push --force-with-lease`.
- If the rebase pulled in non-trivial upstream changes, run the test suite once it finishes; a clean textual rebase can still be semantically broken.

Finally, capture the intent: what the user set out to accomplish, in their terms, plus the deliberate decisions and tradeoffs made along the way.
You know this from the conversation; do not re-read files to reconstruct it.
Both reviewers below and the PR body all need it, and it is what separates "deliberate choice" from "mistake" in every judgment call below.

## Phase 1: Adversarial review

Review the branch with fresh eyes before anything else.
You wrote this code, so do not review it yourself, and do not run the diff in your own context; the reviewer produces and reads it in theirs.

Launch one subagent with no authoring context.

Give the subagent:

- The command to produce the diff: `git diff $(git merge-base origin/<default-branch> HEAD)...HEAD`.
- The intent paragraph from phase 0.
- Instructions to review adversarially: assume the change is wrong somewhere and go looking for it.
  Correctness, reliability, security, broken edge cases, missing tests, things the diff claims to do but does not.
- Instructions to return only a findings list (no diff excerpts beyond the minimal offending lines), each with a severity (`error`, `warning`, `info`), file and line, a one-to-two sentence description, and a classification:
  - `fix`: a genuine defect or omission.
  - `intent`: the finding challenges a decision the intent says was deliberate, or changes product behavior.
  - `note`: informational; no action needed.
- Instructions to judge against the intent: something the user explicitly chose is not a finding, however unusual it looks in the diff.

### Responding to it

Act on the list in one pass before moving on:

- Fix every `fix` finding yourself and commit on the same branch.
  Do not launch a second review subagent to re-check; the test suite is the recheck.
- Bring `intent` findings to the user verbatim and let them decide, unless they asked you to run unattended, in which case use your judgment and flag the decision in the final summary.
- If the repo has test and lint commands, run them now and fix what fails.

## Phase 2: CodeRabbit review

Only once phase 1 is fully responded to, run CodeRabbit locally.
CodeRabbit is the same reviewer that comments on the PR; every finding it returns here is a review round that never happens on GitHub, which is the whole point of running it before the push.
Running it after the adversarial fixes means it reviews the code you will actually push, not a draft.

Prefer its own subagent, which keeps the review out of your context:

- Launch the `coderabbit:code-reviewer` subagent and ask it for the findings on the branch's **committed** changes against `<default-branch>`.
  Scope matters: CodeRabbit reviews the whole worktree by default, which would pull in the unrelated local edits phase 0 told you to preserve and report them as branch findings.
- If that subagent is not available (the plugin is not installed on this machine), launch a plain subagent to run `coderabbit review --committed --base <default-branch>` and report back only the findings - never pipe that output into your own context.
- If the `coderabbit` binary is missing or `coderabbit auth status` fails, say so in one line and skip to phase 3.
  Do not try to install or authenticate it yourself; it is declared in the nix flake and `coderabbit auth login` is the user's to run.

CodeRabbit does not run tests, by design.
CI does that, and phase 4 reads the results.

### Responding to it

Classify its findings by the same `fix` / `intent` / `note` scheme and act on them exactly as in phase 1.
Drop anything that duplicates a phase 1 finding you already handled.
Re-run tests and lint after the fixes, and do not push with a locally failing suite.

## Phase 3: Push and PR

- Push the branch: `git push -u origin HEAD`.
  If the phase 0 rebase rewrote history on an already-pushed branch, use `git push --force-with-lease -u origin HEAD` instead.
  Never use a bare `--force`.
- If no PR exists (`gh pr view` fails), create one with `gh pr create`.
  Structure the body as: `## Intent` (the phase 0 paragraph), `## What changed`, `## Testing` (what you ran and what the reviews found).
- If a PR already exists, the push updates it; refresh the body with `gh pr edit --body` only if the change's shape moved materially.

## Phase 4: CI and merge conflicts

Watch until checks are green and the PR is mergeable.

1. Block on checks with one self-contained Bash call.
   CI taking many minutes is normal; give the call a long timeout or run it in the background, and never kill it because it seems slow.

   ```sh
   while true; do
     b=$(gh pr checks --json bucket --jq '[.[].bucket] | unique | join(",")' 2>/dev/null) || { echo "NO CHECKS"; break; }
     case "$b" in
       *fail*|*cancel*) echo "FAIL: $b"; break ;;
       *pending*)       sleep 60 ;;
       *)               echo "PASS: $b"; break ;;
     esac
   done
   ```

2. If checks fail, do not read the logs yourself.
   Spawn a subagent to run `gh run list --branch <branch> --limit 5` and `gh run view <run-id> --log-failed`, and report back only the failing job, the root cause, and the few relevant error lines.
   Make the smallest root-cause fix, commit, push, and return to step 1.
   Give up after 3 fix attempts for the same failure and report it to the user instead of thrashing.
3. Check mergeability:

   ```sh
   gh pr view --json mergeable,mergeStateStatus --jq '"\(.mergeable) \(.mergeStateStatus)"'
   ```

   Phase 0 already rebased, so this should be clean; it catches the case where the default branch moved while you were working.
   On `CONFLICTING` or `DIRTY`: repeat the phase 0 rebase, resolve conflicts with the smallest correct resolution, then `git push --force-with-lease`, and return to step 1.
   A PR that is merely behind but clean needs nothing.

## Phase 5: PR review loop

Drive the bots' review comments on the PR to resolution.
Both CodeRabbit and Copilot review the PR itself, and both are handled in the same loop because they produce the same kind of thread.
Repeat this loop until a round produces no new actionable comments, up to 10 rounds.

1. Count existing bot reviews, then request a fresh round from both:

   ```sh
   gh api repos/{owner}/{repo}/pulls/{pr}/reviews \
     --jq '[.[] | select(.user.login | test("copilot-pull-request-reviewer\\[bot\\]|coderabbitai\\[bot\\]"))] | length'
   gh pr edit --add-reviewer @copilot
   gh pr comment --body '@coderabbitai review'
   ```

   Re-requesting only triggers a fresh review when the head has new commits since the last one; on an unchanged head treat "no new review appears" as done, not as a failure.
   If either request errors, that reviewer is not available on this repo; say so in one line and carry on with the other.
2. Wait for a review to land in one Bash call, not repeated polls:

   ```sh
   n=<count-from-step-1>; t=0
   while [ "$t" -lt 600 ]; do
     c=$(gh api repos/{owner}/{repo}/pulls/{pr}/reviews \
       --jq '[.[] | select(.user.login | test("copilot-pull-request-reviewer\\[bot\\]|coderabbitai\\[bot\\]"))] | length')
     [ "$c" -gt "$n" ] && { echo "REVIEW LANDED"; exit 0; }
     sleep 30; t=$((t+30))
   done
   echo "TIMEOUT"
   ```

   On timeout, tell the user which reviewer never responded and carry on with whatever did land.
3. Fetch the actionable threads, letting `--jq` trim the response before it reaches you:

   ```sh
   gh api graphql -f query='
     query($owner: String!, $repo: String!, $pr: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $pr) {
           reviewThreads(first: 100) {
             nodes {
               id isResolved isOutdated path line
               comments(first: 1) { nodes { databaseId author { login } body } }
             }
           }
         }
       }
     }' -f owner=<owner> -f repo=<repo> -F pr=<number> \
     --jq '.data.repository.pullRequest.reviewThreads.nodes
           | map(select((.isResolved or .isOutdated) | not)
                 | {id, path, line, author: .comments.nodes[0].author.login,
                    commentId: .comments.nodes[0].databaseId, body: .comments.nodes[0].body})'
   ```

   This returns human threads too.
   Fix or reply to those on their merits as well, but never resolve a human's thread: leave it for them.
4. Judge each bot comment on its merits against the intent; both bots are frequently wrong or pedantic, and agreeing with a bad suggestion is worse than pushing back.
   - Valid point: fix it in code.
   - Wrong, or challenging a deliberate decision: no code change; the reply explains why, citing the intent.
5. For each handled bot thread, reply and resolve in the same Bash call, keeping only a one-line confirmation:

   ```sh
   gh api repos/{owner}/{repo}/pulls/{pr}/comments/<commentId>/replies -f body='...' --jq '.id'
   gh api graphql -f query='
     mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }' \
     -f id=<thread-id> --jq '.data.resolveReviewThread.thread.isResolved'
   ```

6. If step 4 produced code changes: commit, push, run phase 4 again, then return to step 1 for a re-review.
   If it produced no code changes, the loop is done.

After 10 rounds with comments still arriving, stop and summarize what remains rather than looping forever.
Ten rounds is deliberately generous: the bots routinely need several passes, and stopping early leaves the PR in a worse state than not starting.

## Finish

Report to the user in one readable summary:

- The PR link and its state (checks green, mergeable, review threads resolved).
- What each pre-push review found and fixed, the adversarial review and CodeRabbit counted separately, plus each CI failure fixed and each conflict rebased away.
- Each PR review comment with a one-line verdict: fixed, or rejected and why.
- Any open human review threads, left alone for them.
- Any judgment call made on their behalf while running unattended.

Then hand over: the user reviews and merges.
