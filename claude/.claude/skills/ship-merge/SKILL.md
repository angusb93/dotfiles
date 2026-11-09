---
name: ship-merge
description: Everything the ship skill does - adversarial review, CodeRabbit, PR, CI and review comments - and then keeps auto-fixing until the PR actually merges into the default branch. Use when the user asks to ship and merge, land it, get it merged, merge it when green, or invokes /ship-merge.
---

# ship-merge

Take the current branch all the way into the default branch, unattended.

This skill is `ship` plus a merge.
Everything up to a green, review-clean PR is identical, so do not re-derive it: read and follow `~/.claude/skills/ship/SKILL.md` phases 0 through 5 in full, with the two differences below, then come back here for phase 6.

## Differences from ship

- **Do not stop at hand-over.** `ship`'s "Finish" section hands the PR to the user to merge. Here you merge it yourself.
- **Run unattended.** `ship` pauses on `intent` findings to let the user decide. Here you do not pause: judge each `intent` finding yourself against the captured intent, act, and record the call for the final summary.
  The one exception is a decision that is genuinely the user's rather than a judgment call - deleting data, changing a public interface, anything the intent does not cover and you cannot justify from it. Stop and ask for those.
- **The review loop is not optional.** `ship` allows the CodeRabbit or Copilot request to fail and carries on. Here, if both bots are unavailable on the repo, say so plainly in the summary: you are merging with only the local reviews behind it.

## Phase 6: Merge

Loop until the PR is merged or you genuinely cannot get it there.

1. Confirm the PR is actually ready before merging. All three must hold:

   ```sh
   gh pr view --json mergeable,mergeStateStatus,reviewDecision \
     --jq '"\(.mergeable) \(.mergeStateStatus) \(.reviewDecision)"'
   gh pr checks --json bucket --jq '[.[].bucket] | unique | join(",")'
   ```

   - checks are all `pass` or `skipping`,
   - `mergeable` is `MERGEABLE`,
   - no unresolved review thread remains, bot or human.

   Never merge past a failing check, and never merge past an unresolved human review thread: a human blocking the PR outranks this skill. Stop and tell the user instead.
2. If `reviewDecision` is `REVIEW_REQUIRED` or `CHANGES_REQUESTED`, you cannot merge. Report what is blocking and stop; approvals are not yours to grant or bypass.
3. Merge with the repo's convention. Prefer squash unless the repo clearly uses merge commits or rebase merges:

   ```sh
   gh pr merge --squash --delete-branch
   ```

   Keep the squash commit message conventional, with scope and ticket number, matching the PR title.
4. If the merge is rejected because the base moved under you, re-run `ship` phase 0's rebase, force-push with `--force-with-lease`, re-run `ship` phase 4 to get green again, and return to step 1.
5. If CI goes red on a re-run, fix it as `ship` phase 4 step 2 describes and come back.

Give up after 3 full passes through this loop and report what is still blocking rather than thrashing against it.

Never enable auto-merge as a substitute for this loop. The point of the skill is that you watch and fix; auto-merge would land the PR without you seeing what happened.

## Finish

Report everything `ship`'s Finish section asks for, plus:

- Whether it merged, and the merge commit.
- Every judgment call you made on the user's behalf while unattended, as a short list. This is the part they will actually read, because it is the only thing they did not get to decide.
- Anything you merged with that you would have flagged if they had been watching.
