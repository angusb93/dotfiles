---
name: ship
description: Review committed changes with fresh eyes, open or update a PR, watch CI and merge conflicts until green, then drive Copilot review comments to resolution. Use when the user asks to ship, ship it, push safely, babysit a PR, handle Copilot comments, or invokes /ship.
---

# ship

Validate the current branch's changes, get them onto a PR, and babysit that PR until CI is green and every Copilot review comment is resolved.
You drive everything yourself with `git` and `gh`.
Never merge the PR; merging is the user's call.

## Token discipline

This skill runs long waits against chatty APIs, and every byte of output you pull into your context is paid for again on every subsequent call.
Follow these rules throughout:

- Never poll with repeated tool calls.
  Do all waiting inside a single Bash call that loops with `sleep` and prints one final status line.
- Never pull raw JSON or full logs into your context.
  Filter every `gh` call with `--jq` down to the exact fields you need.
- Send bulky reading (the diff, failing CI logs) to a subagent and keep only its conclusions.

Work through the four phases in order.
Phases 3 and 4 loop: a push made while handling Copilot comments sends you back to the CI watch before re-requesting review.

## Phase 0: Preconditions

- The work must be committed.
  If there are uncommitted changes that belong to the task, commit them with a conventional commit message.
  Preserve unrelated pre-existing changes; never sweep them into your commits.
- You must be on a feature branch.
  If on the default branch, create a feature branch first and move the work there.
- `gh auth status` must succeed.

Capture the intent before anything else: what the user set out to accomplish, in their terms, plus the deliberate decisions and tradeoffs made along the way.
You know this from the conversation; do not re-read files to reconstruct it.
The reviewer in phase 1 and the PR body both need it, and it is what separates "deliberate choice" from "mistake" in every judgment call below.

## Phase 1: Fresh-eyes review

Review the branch before it leaves the machine.
You wrote this code, so do not review it yourself: launch one subagent with no authoring context.
Do not run the diff in your own context; the subagent produces and reads it.

Give the subagent:

- The command to produce the diff: `git diff $(git merge-base origin/<default-branch> HEAD)...HEAD`.
- The intent paragraph from phase 0.
- Instructions to return only a findings list (no diff excerpts beyond the minimal offending lines), each with a severity (`error`, `warning`, `info`), file and line, a one-to-two sentence description, and a classification:
  - `fix`: a genuine defect or omission; correctness, reliability, security, or a broken edge case.
  - `intent`: the finding challenges a decision the intent says was deliberate, or changes product behavior.
  - `note`: informational; no action needed.
- Instructions to judge against the intent: something the user explicitly chose is not a finding, however unusual it looks in the diff.

Then act on the findings in one pass:

- Fix every `fix` finding yourself and commit on the same branch.
  Do not launch a second review subagent to re-check; the test suite is the recheck.
- Bring `intent` findings to the user verbatim before pushing and let them decide, unless they asked you to run unattended, in which case use your judgment and flag the decision in the final summary.
- If the repo has test and lint commands, run them now and fix what fails.
  Do not push with a locally failing suite.

## Phase 2: Push and PR

- Push the branch: `git push -u origin HEAD`.
- If no PR exists (`gh pr view` fails), create one with `gh pr create`.
  Structure the body as: `## Intent` (the phase 0 paragraph), `## What changed`, `## Testing` (what you ran and what the review found).
- If a PR already exists, the push updates it; refresh the body with `gh pr edit --body` only if the change's shape moved materially.

## Phase 3: CI and merge conflicts

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

   On `CONFLICTING` or `DIRTY`: fetch, rebase onto `origin/<default-branch>`, resolve conflicts with the smallest correct resolution, then `git push --force-with-lease`, and return to step 1.
   A PR that is merely behind but clean needs nothing.

## Phase 4: Copilot review loop

Drive Copilot review comments to resolution automatically.
Repeat this loop until a round produces no new actionable comments, up to 2 rounds.

1. Count existing Copilot reviews, then request one:

   ```sh
   gh api repos/{owner}/{repo}/pulls/{pr}/reviews \
     --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | length'
   gh pr edit --add-reviewer @copilot
   ```

   Re-requesting only triggers a fresh review when the head has new commits since Copilot's last review; on an unchanged head treat "no new review appears" as done, not as a failure.
   If the request itself errors, Copilot review is not available on this repo; say so and finish.
2. Wait for the review to land in one Bash call, not repeated polls:

   ```sh
   n=<count-from-step-1>; t=0
   while [ "$t" -lt 600 ]; do
     c=$(gh api repos/{owner}/{repo}/pulls/{pr}/reviews \
       --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | length')
     [ "$c" -gt "$n" ] && { echo "REVIEW LANDED"; exit 0; }
     sleep 30; t=$((t+30))
   done
   echo "TIMEOUT"
   ```

   On timeout, tell the user Copilot never responded and finish with the PR link.
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
                 | select(.comments.nodes[0].author.login == "copilot-pull-request-reviewer[bot]")
                 | {id, path, line, commentId: .comments.nodes[0].databaseId, body: .comments.nodes[0].body})'
   ```

4. Judge each comment on its merits against the intent; Copilot is frequently wrong or pedantic, and agreeing with a bad suggestion is worse than pushing back.
   - Valid point: fix it in code.
   - Wrong, or challenging a deliberate decision: no code change; the reply explains why, citing the intent.
5. For each handled thread, reply and resolve in the same Bash call, keeping only a one-line confirmation:

   ```sh
   gh api repos/{owner}/{repo}/pulls/{pr}/comments/<commentId>/replies -f body='...' --jq '.id'
   gh api graphql -f query='
     mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }' \
     -f id=<thread-id> --jq '.data.resolveReviewThread.thread.isResolved'
   ```

6. If step 4 produced code changes: commit, push, run phase 3 again, then return to step 1 for a re-review.
   If it produced no code changes, the loop is done.

After 2 rounds with comments still arriving, stop and summarize what remains rather than looping forever.

## Finish

Report to the user in one readable summary:

- The PR link and its state (checks green, mergeable, Copilot threads resolved).
- What the fresh-eyes review found and fixed before push, each CI failure fixed, and each conflict rebased away.
- Each Copilot comment with a one-line verdict: fixed, or rejected and why.
- Any judgment call made on their behalf while running unattended.

Then hand over: the user reviews and merges.
