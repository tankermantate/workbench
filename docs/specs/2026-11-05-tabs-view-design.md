# Tabs view (`wb-tabs`)

With many tabs open across spaces there is no one place to see what each is doing, and a session
stuck waiting on you costs time until you happen to notice it. `wb-tabs` prints every open terminal
tab grouped by what it needs from you. Two things bring the news to you without opening it: a
Terminal bell on the tab, and a yellow count on the launcher.

## Facts this rests on

Measured on 2026-11-05, with 11 tabs open over 3 bead stores (the largest has 1,327 issues).
The first plan used `bd show` per tab and treated `last-<tty>` as the map from tab to session.
Neither survived measuring.

| Fact | Consequence |
|---|---|
| `bd show` rewrites `.beads/last-touched`, the target of a bare `bd close` or `bd update` | A view must never call it: it could point another tab's bare close at the wrong bead. `bd list` leaves that file alone (the Dolt manifest's mtime moves, its content doesn't). |
| 11 `bd show` calls: 4.4s serial, 7.4s parallel on one store (it contends with itself), 2.9s batched | One read per store. |
| One full `bd list --all` per store, stores in parallel: 0.75s | That read, which also carries parents. Parents often can't be derived from an id, and a second `--id` pass costs as much as the full list. |
| `last-<tty>` is a title string the user's status line writes, and it outlives the session | The view doesn't read it: the space and bead already say what the title would. |
| `<claude config>/sessions/<pid>.json` holds `sessionId`, `cwd`, `status`, `statusUpdatedAt`; it matched 10 of 10 live claudes | This is the join. |
| `status` is `busy`, `idle` or `waiting`, and `waiting` carries a `waitingFor` reason. Measured 2026-11-05: a question prompt went to `waiting` / `input needed` within 2s | "Stuck on a prompt" needs no hook and no global settings, so it covers tabs the launcher didn't start. |

## How a row is built

    ps  ->  tty, claude pid  ->  <config>/sessions/<pid>.json  ->  $WB_STATE_DIR/sessions/<sessionId>.json

- **ps decides what's live.** Every tty with a process is a tab; a leftover `last-<tty>` adds
  none. The outermost `claude` on a tty is the session, so a `claude -p` it spawned isn't.
- **Config dirs** are `~/.claude`, `$CLAUDE_CONFIG_DIR` and each space's `claude_config`. If a
  pid has a file in two, the newest `startedAt` wins, since a recycled pid can leave an old one.
- **The session record names the bead**, never `WB_BEAD` in the process's environment:
  `wb-focus` moves sessions, so the environment goes stale.
- **Space and worktree** come from the pid file's `cwd` through `lib/wb_space.py`, the same
  logic the status line uses. A session left open after `end-session` removed its worktree has a
  `cwd` that says nothing, so its record's root names the space instead.
- **Idle time** is `statusUpdatedAt`, which matched each session's last assistant message. A
  transcript's mtime would not do: it moves about every minute, even in an idle session.
- **Beads** are read once per store, with the store resolved from the record's root, so two
  spaces in one repo don't make two contending calls.

| Tab | Row reads |
|---|---|
| No claude on the tty | `plain shell` |
| Claude, no pid file or an unreadable one | `unbound`, `status unknown` |
| Claude, no record, not launched by workbench | `unbound` |
| Claude, no record, `WB_SPACE_ROOT` in its environment | `no bead` |
| Claude with a record | the bead and its status |

## The groups

| Group | Rule | Status reads |
|---|---|---|
| Waiting on you: blocked | status is `waiting`, whatever the bead says | `blocked · input needed · 2m` |
| Waiting on you: your turn | `idle`, and the bead isn't closed | `your turn · 5h` (`bead blocked` or `bead deferred` is added when it applies) |
| Working | `busy` | `working · 2m` |
| Nothing pending | `idle`, and the bead is closed or not found, or there is none; or a status this view doesn't know | `closed · 2h`, `idle · 1m`, `bead not found`, the status as it came |

A session that asks a question in plain text and stops reads as `idle`, which is why "your turn"
exists. A tab with no bead counts as nothing pending, even if its session asked something: there's
no bead to say the work is still open.

If bd can't answer, an idle tab on a bead stays under waiting and says so: it may need you, and a
view for catching that shouldn't hide it. A record saying the session closed its bead still reads
`closed`.

`ps -E` is only asked about the sessions with no record, and only that one variable is looked
for: a process's environment can hold secrets, so nothing else is read from it or kept.

## Decisions on the bead's open questions

1. **Summaries are deterministic.** Goal is the description's first sentence of five words or more
   (a shorter one is usually where the bead came from: "Split from x."), without a leading
   `WHY:`. Next is the latest note line (a worktree-claim line isn't news), or
   `no next step recorded`. A model only if these read badly in use; nothing here is cached.
2. **No AppleScript for tab titles.** It would bring an Automation permission prompt and more
   latency to a command meant to be instant, and only work in one terminal. Jumping to a tab does
   use it, because the cost then falls only on a pick, not on the view.
3. **ps is the source of truth for live tabs**, as above.
4. **No binding means `unbound`**, never a guess from the title or folder. The space is still
   shown, since the folder does say that.

## Failing soft

`sessions/<pid>.json` is Claude Code's internal, undocumented file: if it's missing or changes
shape, those tabs read `unbound` and `status unknown` under nothing pending, and nothing breaks.

A store's read has a deadline (`WB_TABS_BD_TIMEOUT`, default 2s). Past it, or if bd fails, that
store's tabs keep the title from the session record and say `bead status unknown (bd didn't
answer)`, so one slow store can't hold up the view. They have no goal or next line. The other rows
are unaffected. So: ~1s normally, about 2s at worst.

If `ps` itself fails there's no truth about what's live, so `wb-tabs` says so and exits 1.

## Layout

One row per tab, in columns, the way the launcher's first screen reads: name on the left, summary on
the right. Only waiting tabs get goal and next lines, because those are the tabs needing a decision.
Those tabs have a blank line between them; one-line rows stay together. Plain shells come last. The heading is yellow on a terminal. A worktree is just `⑂` beside the space:
its long folder name pushed everything else off the line.

    WAITING ON YOU (2)
      Acme    41q  Resend the order email    blocked · input needed · 2m
          goal  Customers lose the email when the mail provider times out.
          next  retry added, deploy pending

      Acme ⑂  60g  Refund limits             your turn · 1d
          goal  Refunds over the limit need a person to approve them.
          next  no next step recorded

    WORKING (1)
      Globex  x1y  Trim the footer           working · 40s

    NOTHING PENDING (2)
      Acme    6pg  Pager crash on page two   closed · 1h
      plain shell

On a terminal the title gives way so the status column stays readable, then any line still too long
is cut to the width. Pipes get whole lines.

## Reaching you

**The bell.** Claude Code's own `preferredNotifChannel: "terminal_bell"`, set in each Claude config
dir's `settings.json`, rings when a session finishes or pauses for permission and you appear to be
away. Apple Terminal then shows a bell on that tab. It's the user's setting, not this repo's, and no
workbench code runs for it.

**A blink was tried and dropped.** A throwaway test alternated a tab's title and a launcher row. It
worked, and was annoying. So was a background watcher to drive it, which nothing now needs.

**The launcher.** `wb-tabs --waiting` prints `{"total": n, "spaces": {label: n}}`, and it never reads
another process's environment. `wb-ui fill-counts` runs it alongside the space counts, into
`TMP/waiting.json`, so drawing the screen doesn't wait for it. A space's row gets a yellow
`N waiting on you` before its summary, `✦ open tabs` gets the total, and a folder in no space counts
only in the total. Waiting means blocked or your turn; the view tells them apart. If it fails or takes
over 3s the rows just show no count, and an earlier count is removed rather than left standing.

The count is right as of when the screen was drawn and doesn't update live; the bell covers changes
while the launcher is open.

## Going to a tab

With fzf, choosing `✦ open tabs` opens the view as a list, from `wb-tabs --rows`: `tty<TAB>line`, sized
to `$COLUMNS` less fzf's gutter. All of a tab's lines carry its tty, so its goal or next line goes
there too; headings and blanks carry `-`, and picking one does nothing. Enter or a double-click goes
to the tab, through `wb-tabs --jump TTY`, and the launcher's tab returns to screen 1, which re-reads
its counts. Esc returns there too. `ctrl-r` re-reads the list.

`--jump` selects the tab with `osascript`, in Apple Terminal only, with the tty passed as an argument
after it's checked to be `ttysNNN`. On the Mac it was built on, macOS asked for no permission; another
Mac might ask for Automation permission. If that's declined, the tab has closed or it's another terminal, it says so and waits for Enter, then returns to the list.

Without fzf, or if fzf itself fails, the view prints as before and waits for Enter. A view longer than
the window scrolls: there is no pager, because `wb-tabs` only cuts lines to fit when it's printing
straight to the terminal.

## Not built

- Anything that writes, caches or spawns a model.
- Blinking, a background watcher, a status line segment, jumping in any terminal but Apple Terminal.
