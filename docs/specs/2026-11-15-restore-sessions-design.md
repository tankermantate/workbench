# Save and restore sessions (`wb-restore`)

Running twenty-odd Claude sessions at once is the point of workbench, but a Mac that stays up for
months fills its swap, and the cure is a restart. A restart closes every tab. Without a way to
bring them all back, the restart keeps getting put off. `wb-restore save` records every open
session; after the restart, `wb-restore` opens a tab for each one and resumes it where it was.

## Facts this rests on

Measured on 2026-11-15, with 18 sessions open over two Claude accounts.

| Fact | Consequence |
|---|---|
| `<claude config>/sessions/<pid>.json` holds `sessionId`, `cwd` and `kind`, and the folder it sits in is the session's account | The snapshot is built from these, as `wb-tabs` joins them. The account is the folder the pid file was found in, not a guess. |
| `claude --resume <id>` keeps the session id (`--fork-session` is the opt-in for a new one), and finds the transcript by the folder it runs in | Resume in the saved `cwd`. A folder that is gone (end-session removed its worktree) can't be resumed, so it's shown as skipped. The workbench session record, keyed by session id, still binds after a resume. |
| A window Terminal opens for `do script` is a fresh interactive shell, and the launcher starts at its first prompt and reads the tty | Typing a command into a new window races the launcher's fzf screen. Instead the launcher itself claims one queued session at its first prompt and resumes it. |
| A process's argv holds the launcher's opening prompt | Only whether `--dangerously-skip-permissions` is there is kept. Replaying argv would send the opening prompt again. |

## Saving

`wb-restore save` writes `$WB_RESTORE_DIR/snapshots/<UTC time>.json` (default
`~/.local/state/workbench/restore`). It holds one entry per live interactive session:

    {"session": id, "cwd", "config": the pid file's folder, "skip_permissions": bool,
     "name": Claude's session name, "space_root", "bead", "worktree", "repo", "branch"}

`space_root` and `bead` come from the workbench session record; `worktree` is the `cwd`'s git
top level when that is a linked worktree, with its main repo and branch. Nothing comes from a process's environment. It reads
`ps`, the pid files and the session records, and never `bd`, so it is cheap enough to run on a
schedule: `install.sh` loads a launch agent (`workbench.restore-save`) that runs
`wb-restore save --quiet` every 10 minutes, so a crash or a forced restart is covered without
anyone remembering to save. Sessions the launcher starts also save at their start and end:
`wb-session-hook` runs `wb-restore save --quiet` in the background, a few seconds after
`SessionStart` (so the new session's pid file is there) and after `SessionEnd` with
`--without <its id>` (it is still running while its hook does). A session opened or closed since
the last 10-minute save is then still right after a crash. A snapshot with the same sessions as the newest one isn't written
again, and snapshots older than 7 days are pruned (the newest is always kept). A save that finds
no sessions open while the newest snapshot is from before this boot writes nothing: nothing has
been reopened since the restart, and an empty snapshot would otherwise be the one the restore
after a second restart picks. Closing everything on purpose is still recorded once a snapshot
from this boot exists.

A live claude with no pid file in any known config dir means the snapshot would miss a session,
most likely because `wb-spaces` couldn't read the spaces and so their accounts aren't known.
Save then writes nothing and exits 1: the last whole snapshot stays the one a restore uses.

## Restoring

`wb-restore` (no subcommand) picks a snapshot: the newest taken before this boot
(`kern.boottime`; `WB_BOOTTIME` fakes it), or the newest overall when none is. It then drops:

- sessions still live: a pid file of a running claude names the same id. Two processes on one
  transcript is the one thing a restore must never cause, and running `wb-restore` twice or
  before the restart would otherwise do it;
- sessions whose folder is gone, listed as skipped with the reason. For a worktree the snapshot
  also keeps its main repo and branch, so the reason can tell an ended worktree (its branch is
  gone too: the work was finished) from a removed one whose branch is left, which may hold work.
  For that one it prints the `git worktree add` that brings the folder back at the same path; the
  next `wb-restore` then resumes the session. It doesn't recreate the folder itself, so the
  space's `on_create` setup is the user's to run if the worktree needs it.

What's left is offered in fzf, all selected (Tab unticks); without fzf, a yes/no for all of them.
With no terminal to answer on (input ends before any answer, as from a Claude `!` prompt) it
resumes nothing, exits 1 and says to rerun with `--yes`, which takes all of them without asking.
The chosen sessions go into `$WB_RESTORE_DIR/queue/` as one file each, then one osascript call
asks Terminal for one new window per session (macOS's "prefer tabs" setting decides whether they
arrive as tabs). `WORKBENCH_DRY_RUN` prints what it would queue and open instead.

## Offering it, after a restart

A tab's first prompt, when nothing is queued for it to claim, runs `wb-restore count` before the
launcher: the number of sessions in the snapshot from before this boot that would be ready (not
open, not queued, folder still there). It prints 0 when there is no snapshot from before the boot,
when the boot time can't be read, or when the offer was declined since this boot. Above 0, the tab
asks `N sessions were open before the restart. Bring them back? [Y/n]`. Enter runs `wb-restore`
(its picker, then a new tab per session) and the launcher follows; `n` runs `wb-restore decline`, which
writes this boot's time to `$WB_RESTORE_DIR/declined`, so later tabs don't ask until the next
restart. Once they are all open or queued the count is 0 and the question stops by itself.

## Claiming, in each new tab

At the first prompt, after every auto-start guard has passed, the launcher runs
`wb-restore claim`. It moves the oldest queued entry to `claimed/` with an atomic rename (two
tabs starting together can't take the same one) and prints its folder and path. The shell `cd`s
there and runs `wb-restore exec <entry>`, which replaces itself with:

    env CLAUDE_CONFIG_DIR=<config> (or unset, for ~/.claude) [WB_SPACE_ROOT WB_BEAD WB_WORKTREE] \
      claude --settings <wb-session-hook settings-file> [--dangerously-skip-permissions] --resume <id>

When Claude exits, the tab is a shell in the session's folder, as after a launch. With nothing
queued, the launcher starts as usual. An entry older than 5 minutes is deleted unclaimed, so a
tab opened tomorrow never resumes something by surprise.

## Saying when a restart is due

`wb-health` prints one line, such as `up 162 days · swap 41 GB on 32 GB RAM`, and adds
`restart soon: wb-restore brings your tabs back` at 30 days up or when swap in use reaches half
of RAM. Swap is measured against RAM, not against its own total: macOS grows the swap files to
fit, so used/total sits near 100% whether the machine is struggling or not (measured 2026-11-15:
41.6 of 43 GB). The launcher puts the line under the keys in its space and tabs screens' fzf
headers, yellow when due, and above the numbered menu without fzf. It reads three sysctls,
never fails and never waits: what it can't read it leaves out. `WB_BOOTTIME`, `WB_SWAPUSAGE`
and `WB_MEMSIZE` fake them.
