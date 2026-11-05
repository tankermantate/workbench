# Tabs view (`wb-tabs`)

With many tabs open across spaces there is no one place to see what each is doing. `wb-tabs`
prints every open terminal tab: its title, space and worktree, bead, goal and status.

## Facts this rests on

Measured on 2026-11-05, with 11 tabs open over 3 bead stores (the largest has 1,327 issues).
The first plan used `bd show` per tab and treated `last-<tty>` as the map from tab to session.
Neither survived measuring.

| Fact | Consequence |
|---|---|
| `bd show` rewrites `.beads/last-touched`, the target of a bare `bd close` or `bd update` | A view must never call it: it could point another tab's bare close at the wrong bead. `bd list` leaves that file alone (the Dolt manifest's mtime moves, its content doesn't). |
| 11 `bd show` calls: 4.4s serial, 7.4s parallel on one store (it contends with itself), 2.9s batched | One read per store. |
| One full `bd list --all` per store, stores in parallel: 0.75s | That read, which also carries parents. Parents often can't be derived from an id, and a second `--id` pass costs as much as the full list. |
| `last-<tty>` is a title string the user's status line writes, and it outlives the session | It's only ever a title, and only while that tty's live claude is newer than it. |
| `<claude config>/sessions/<pid>.json` holds `sessionId`, `cwd`, `status`, `statusUpdatedAt`; it matched 10 of 10 live claudes | This is the join. |

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
| Claude, no pid file or an unreadable one | `unbound` |
| Claude, no record, not launched by workbench | `unbound` |
| Claude, no record, `WB_SPACE_ROOT` in its environment | `no bead` |
| Claude with a record | the bead, its goal and its status |

`ps -E` is only asked about the sessions with no record, and only that one variable is looked
for: a process's environment can hold secrets, so nothing else is read from it or kept.

## Decisions on the bead's open questions

1. **Summaries are deterministic.** Goal is the description's first sentence of five words or more
   (a shorter one is usually where the bead came from: "Split from x."), without a leading
   `WHY:`, after the parent's title. Status is the bead's state, the session's state
   with its age, then the close reason or latest note line (a worktree-claim line isn't news).
   A model only if these read badly in use; nothing here is cached.
2. **No AppleScript for tab titles.** It would bring an Automation permission prompt and more
   latency to a command meant to be instant, and only work in one terminal. `last-<tty>` shows
   what the status line last set, which is what the tab shows for a Claude tab. A plain shell
   gets no title rather than a stale one.
3. **ps is the source of truth for live tabs**, as above.
4. **No binding means `unbound`**, never a guess from the title or folder. The space is still
   shown, since the folder does say that.

## Failing soft

`sessions/<pid>.json` is Claude Code's internal, undocumented file: if it's missing or changes
shape, those tabs read `unbound` and nothing breaks.

A store's read has a deadline (`WB_TABS_BD_TIMEOUT`, default 2s). Past it, or if bd fails, that
store's tabs keep the title from the session record and say `bead status unknown (bd didn't
answer)`, so one slow store can't hold up the view. The other rows are unaffected. So: ~1s
normally, about 2s at worst.

If `ps` itself fails there's no truth about what's live, so `wb-tabs` says so and exits 1.

## Layout

The bead asked for one row per tab. Five text columns don't fit a terminal, and the goal and
status are the point, so a tab is one block (a plain shell is one line):

    ttys005  🟣 Acme · 41q Order confirmation email
      Acme ⑂ acme-41q · acme-41q Order confirmation email must be resent
      goal    Checkout › Customers lose the email when the mail provider times out.
      status  in_progress · idle 5h · retry added, deploy pending

Lines are cut to the terminal's width only when printing to one.

## On the launcher

Screen 1 has a `✦ open tabs` row after the spaces, since the view covers every space. It runs
`wb-tabs` only when chosen, so drawing the screen costs nothing, and then waits for Enter and
returns to screen 1. A view longer than the window scrolls: there is no pager, because `wb-tabs`
only cuts lines to fit when it's printing straight to the terminal.

## Not built

- Anything that writes, caches or spawns a model.
