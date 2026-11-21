# wb-ship: the steps after the commit

Status: built, November 2026 (wb-kvx.7, vision gap 7).

## Why

A worktree session ended at the commit. Pushing, opening the pull request, watching CI and
merging were left to the user, or to whatever a space's own instructions told Claude, so every
space did it differently and nothing stopped a merge on red or of a commit nobody approved.
`end-session` already refuses to lose work; `wb-ship` is the step before it.

## What it does

`wb-ship [<worktree>] [--yes=<sha>] [--method=merge|squash|rebase] [--wait=<secs>]`, in the
worktree by default:

1. **Refuses** on the default branch, a detached HEAD, uncommitted changes, or no `origin`.
   With every commit already on `origin/<default>`, it says there's nothing to ship (exit 0).
2. **Space**: the worktree space on this repo, picked as `end-session` picks it. Its
   `gh_account` is switched to first, as `new-session` does. That's a switch, not a per-call
   token, because `git push` authenticates through gh's credential helper, which follows the
   active account. Its bead is the one linked to the worktree (`wb-backlog claimed`).
3. **Already merged**: a merged pull request from the branch into the default branch whose
   head is HEAD means it's done (exit 0, with the leaving line below). gh failing to list pull
   requests is a refusal.
4. **Push**: `git push -u origin <branch>`, never forced. A rejected push stops everything.
5. **Pull request**: the open one from this branch into the default branch is reused, else
   `gh pr create --base <default> --head <branch> --fill`. A merged one behind HEAD, or a closed
   one, doesn't block a new one. Opening it is noted on the bead.
6. **CI**: `gh pr checks <n> --json name,bucket,link`, every `WB_SHIP_INTERVAL` seconds (10) for
   up to `--wait` seconds, counted from wb-ship's start (540: Claude's Bash tool stops a
   command at 10 minutes at most). `pass` and
   `skipping` count as passing; `fail` and `cancel` are red; anything else is pending. Checks
   often register a little after the push, so "no checks reported" counts as pending for
   `WB_SHIP_GRACE` seconds (60). After that, a pull request with no checks has no CI, which is
   said and then treated as green.
7. **The space's `before_end`** runs once CI is green, before any yes is asked for or acted on.
   It gets `end-session`'s variables (`WB_SHA` = HEAD, `WB_SPACE`, `WB_WORKTREE`, `WB_PROJECT`,
   `WB_SOURCE`, `WB_BRANCH`, `WB_BEAD`) and runs in the worktree's project folder. A failure is
   exit 1 with its output, and nothing is merged. It has to come before the merge: once the
   branch is merged, `end-session` skips `before_end`, so a gate checked only at close-out
   would never run for shipped work.
8. **Merge, only on a yes.** Red never merges, `--yes` or not. On green:
   - on a terminal it asks `Merge PR #n into main (…)? [y/N]`;
   - with no terminal (Claude) it prints the owner's-call line and `wb-ship --yes=<sha>`
     (exit 10);
   - `--yes=<sha>` must be a prefix (7+ characters) of HEAD, so a yes can't carry over to
     a later commit.

   The merge is `gh pr merge <n> --<method> --match-head-commit <HEAD>`, so GitHub refuses it
   if the pull request's head moved. The method is `--method`, else the repo's
   `viewerDefaultMergeMethod` when it's allowed, else the only allowed one. Otherwise it
   refuses and asks for `--method`. It never passes `--delete-branch` (gh would switch the
   checkout; `end-session` deletes the branch and recognises squash merges), `--admin` or
   `--auto` (auto-merge belongs with review, wb-kvx.18). GitHub refusing (branch protection,
   conflicts) is exit 1 with gh's reason. A merge is noted on the bead, and it prints
   the leaving line: at `/exit` the launcher removes the worktree once its bead is closed (its
   close-out, wb-kvx.22), and a session started without the launcher runs `end-session <worktree>`.

Exit codes: 0 merged, already merged, or nothing to ship · 1 refused, red, or not merged by
GitHub · 2 usage · 10 green, waiting for a yes · 11 checks still running.

## In the flow

The `work-on-bead` prompt gets a fourth step in a worktree space (`{ship}`, filled by the
launcher only when the space has `worktrees = true`). It says to ship with `wb-ship` under a
10-minute timeout, report CI, and run the printed `--yes` only after the owner says yes. Plain spaces have no branch to
ship, so their prompt is unchanged.

## Not here

Review on pull requests and auto-merging low-risk changes (wb-kvx.18), release notes or tags
for a space's own project, and draft pull requests.

## Tests

`tests/test_wb_ship.sh` drives it against a real repo with a bare origin and the fake `gh`
(`pr list/create/checks/merge`, `repo view`):
- refusals and nothing to ship;
- green with no yes (exit 10, no merge), and a yes bound to the SHA;
- red and cancelled, pending then green, still pending at the deadline;
- checks registering after the grace period, skipped checks;
- reuse of an open pull request, already merged, a new pull request after a stale or closed one;
- merge methods, and GitHub refusing the merge;
- the terminal yes and no;
- `before_end` refusing and passing (with its variables), and not run on red;
- bead notes, the gh account switch, a rejected push, and no origin.

`tests/test_handoff.sh` checks the prompt step appears only for worktree spaces.
