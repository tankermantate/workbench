# Launcher — a start screen for every Terminal window

**Status:** shipped · **Date:** 2026-10-16 · **Project 1 of 3** (see Scope)

## Why

Starting work today means remembering four things in order: which alias moves you to which repo
(`acme`), how to see the backlog (`bd ready`, `./scripts/program-overview.sh`), how to start an
isolated session (`new-session <id>`), and the opening prompt to paste. Personal projects have none
of that: no session helper, and bead stores that the installed bd cannot read. So the normal path is
to open Terminal and improvise.

The goal: **open Terminal, and you are already in it.** The backlog is on screen without asking.
You choose a space, then choose existing work or something new, and Claude starts in the right
place, on the right account, already briefed.

## The flow

```
Terminal opens
  → summary of every space (counts only)
  → Space?   Acme | <each personal project> | … | q = plain shell
  → Work?    ✦ something new | <beads in that space, NOW → NEXT → rest, type to filter>
  → Claude starts in that space, with an opening prompt
```

**Space first, then new or existing.** That order is a requirement from the user: name the place
you are working before deciding what to do in it.

### Screen 1: spaces

```
 Acme       NOW 9 · NEXT 16 · unrouted 6 · 2 claimed
 Personal  notes 1 · lens 0 · 8 projects with no beads

 Space?  ›  Acme
            notes
            helper
            …
            [q] just give me a shell
```

- A space with a working bead store shows counts. A project with no store, or one bd cannot read,
  is still listed, because "something new" works anywhere.
- A space whose bd read fails or times out shows `(bd unavailable)` and stays selectable.

### Screen 2: work

```
 Acme  ›  ✦ something new
         ── NOW ──
         ○ k7m2  P1  Supplier invoices arrive without a purchase order number
         ── NEXT ──
         ○ q4n8w P1  Customer portal must show the promised delivery date …
         ── everything else ──
         …
```

- **Type to search** every live bead in the space by short id, title and description, ignoring case. A word
  of 1-2 letters matches only whole or as a plural ("po": "PO", "POs"); a longer word matches from
  the start of a word ("fab": "fabric"). A count line comes first, then the beads matching every
  word, then (below a divider) those matching some. Within each, beads with more of the words in
  the title come first, then the order above. Matched words are highlighted in the list and the
  preview. wb-ui does the matching (`lib/wb_search.py`, shared with the preview), because fzf can
  only search what it shows. The space screen uses fzf's exact, case-insensitive match.
- **The preview pane** shows the highlighted bead's description, its parent epic and its labels.
- **In-progress beads are marked `◐`.** They are probably another session's, so a glance prevents
  a second session on the same bead.
  - Selecting one in a worktree space doesn't call `new-session`, which refuses with
    `worktree path already exists`.
  - If that bead's worktree exists, the launcher offers **resume there**: `cd` into it, then start
    Claude with `--continue`.
  - If it doesn't, the claim is stale, and the launcher shows that rather than guessing.
- **Order:** `wave:1`, then `wave:2`, then everything else by priority. A space that doesn't use
  waves is sorted by priority alone.
- **Deferred and closed beads are hidden.**

### Handoff

| Choice | Worktree space (Acme) | Plain space (personal project) |
|---|---|---|
| Existing bead | `new-session <id> --no-launch`, then `cd` into the worktree it printed, then `claude --dangerously-skip-permissions "<work-on-bead prompt>"` | `cd <project> && claude --dangerously-skip-permissions "<work-on-bead prompt>"` |
| ✦ something new | `new-session <space> --no-launch` (exploratory worktree, timestamp slug), then the same `cd` + `claude` | `cd <project> && claude --dangerously-skip-permissions "<shape-it prompt>"` |

- **Prompts are off for every launch, Acme and personal alike.** That matches `new-session`'s
  default. A space can set `safe = true` to keep prompts on.
- **The launcher, not `new-session`, starts Claude.** `new-session` ends in `exec claude`, which
  leaves the parent shell wherever it started. Running `--no-launch` and then launching Claude
  itself is what puts the shell in the worktree when Claude exits. This needs one small addition
  to `new-session`: with `--no-launch`, print the worktree's project directory as its last line, in
  a parseable form (`WORKTREE_DIR=<path>`).

- **Opening prompts are text files** (`prompts/work-on-bead.txt`, `prompts/something-new.txt`), with
  `{id}`, `{space}` and `{protocol}` placeholders. Edit wording without touching code.
- **The work-on-bead prompt** replaces the paste-this text in Acme's `PROGRAM_PROTOCOL.md`: read the
  space's protocol doc if one is configured, `bd show <id>` in full, re-verify the load-bearing figure,
  then build.
- **The something-new prompt** says: help the user shape the idea; once it has a shape, file a bead,
  under a parent epic if the space has epics, and only then start building. If the space has no
  bead store, `bd init` first.
- **After Claude exits you land in a normal shell** in the session's directory. You don't drop
  back into the launcher.

## Configuration: per machine, never in the repo

`~/.config/workbench/spaces.toml` lists this machine's spaces. The repo ships only
`spaces.example.toml`, with placeholder names. **This is what makes a public repo safe:** no space
names, paths, accounts or employers appear in code.

```toml
[[space]]
name          = "Acme"
root          = "~/dev/acme/acme-app"
beads         = true
worktrees     = true          # launch through new-session
session_cmd   = "new-session" # must accept: <bead-id> | <space-key>, --no-launch
space_key     = "acme"         # what new-session calls this domain
claude_config = "~/.claude-acme"
protocol      = "docs/PROGRAM_PROTOCOL.md"

[[space]]
name          = "Personal"
glob          = "~/dev/personal/*"   # one entry per matching directory
beads         = "if-present"
worktrees     = false
# no claude_config: the default profile
```

- **A glob space** expands into one entry per directory on screen 1, sorted, with project folders
  shown under their group name.
- **`claude_config` is optional**, and only set for a non-default profile. When present, it sets
  `CLAUDE_CONFIG_DIR` for the launched session. When absent, the variable is **left unset**: Claude
  then reads its main config from `~/.claude.json`, whereas `CLAUDE_CONFIG_DIR=~/.claude` would read
  `~/.claude/.claude.json`. On this Mac those differ (88 KB vs 343 B, measured 2026-10-16), so
  pointing the default profile at `~/.claude` would silently swap the account's settings. The Acme
  `claude()` shell function already sets the variable by path; setting it explicitly keeps the
  launcher independent of that function.
- **No config file** prints one line saying where to create it and exits to the shell. No crash, no
  auto-generated file.

## Components

| Unit | Does | Depends on |
|---|---|---|
| `launch` (zsh function in `shell/workbench.zsh`) | Draws the two screens, runs the handoff, and `cd`s the shell. It holds no bead logic. It is a **function, not a `bin/` script**: a child process can't change the parent shell's folder, and landing in the session's folder after Claude exits depends on that. | `wb-spaces`, `wb-backlog`, fzf (numbered-menu fallback) |
| `bin/wb-spaces` | Reads `spaces.toml`, expands globs, prints one line per space. | python3 ≥ 3.11 (stdlib `tomllib`; this Mac has 3.14, the second laptop is unchecked) |
| `bin/wb-backlog <space>` | Prints the space's live beads as tab-separated `id, status, priority, wave, title, parent`, and with `--summary`, one count line. | `bd` |
| `prompts/*.txt` | Opening prompts. | — |
| `shell/workbench.zsh` | Sourced from `~/.zshrc`. Defines `launch` and registers a **run-once `precmd` hook** that decides whether to call it at the first prompt. Running at the first prompt, not partway through `.zshrc`, means everything `.zshrc` defines later (the `claude()` function, aliases, `PATH`) already exists. | — |
| `install.sh` | Links `bin/*` into `~/.local/bin`, prints the one line to add to `~/.zshrc`. Idempotent. Never edits `~/.zshrc` itself. | — |

**One change outside the repo:** with `--no-launch`, `~/scripts/new-session` also prints
`WORKTREE_DIR=<path>` as its last line. That is the only edit to a script every Acme session depends
on. It is additive, and today's `--no-launch` output is otherwise unchanged.

### Reading beads

- **One call per space:** `bd list -n 0 --json` from the space's root. It carries `labels`, `parent`
  and `status`, as Acme's `program-overview.sh` already relies on.
- **Speed (measured 2026-10-16):**
  - **Read times:** an Acme `bd list -n 0 --json` (355 live issues) takes 0.5–0.9 s, a personal
    store about 0.4 s, and a folder with no store 0.06 s.
  - **Screen 1 draws the space list at once**, and the counts fill in as the reads finish, all
    spaces read **in parallel**. The start screen never waits on bd before you can choose.
- **Timeout of 10 seconds per read** (`WB_BD_TIMEOUT`). macOS has no `timeout` command, so
  `wb-backlog` (Python) bounds the read itself. It was 3 seconds until 2026-10-22, when the biggest
  store (1,235 beads) took 1.5–1.9 s alone and about 3 s alongside every other space, so screen 1
  showed it as `(bd unavailable)`. The counts fill in after the screen draws, so a longer limit
  costs nothing unless bd truly hangs.
- **Reads don't disturb running sessions.** Measured on a live store: 40 `bd list` reads running
  alongside 15 `bd update` writes caused zero write failures. So no cache is needed.
- **Empty results.** bd allows one writer at a time, and a locked store has been seen to return
  **empty with exit 0** instead of erroring.
  - So an empty result is retried once.
  - If it's still empty, the space shows `0 open (r to re-check)` rather than a confident `0`.
  - Pressing `r` on screen 2 re-reads.
- **Unreadable stores show `(no readable beads)`** and remain usable for something new. That covers
  `notes`, `atlas` and `done`, which are pre-1.0 JSONL stores. Reviving them is Project 3.

## Auto-start rules (`shell/workbench.zsh`)

`launch` runs at the first prompt only when ALL of these hold:

- the shell is interactive and stdin/stdout are a TTY
- not inside Claude (`CLAUDECODE` unset)
- not VS Code's or another IDE's terminal (`TERM_PROGRAM` is `Apple_Terminal`, or another terminal
  listed in config)
- `WORKBENCH_NO_LAUNCH` is unset (escape hatch: `WORKBENCH_NO_LAUNCH=1` in the environment)
- not a nested shell (`SHLVL` is 1)

**Windows vs tabs.** Apple Terminal opens new tabs in the current tab's folder, which is often a
worktree. The launcher opens there too (changed 2026-10-19, wb-dh5: a repo used to keep it closed,
but tabs are the usual way in). So:

- **every new window and tab** shows the launcher
- **`q`** gives a plain shell in the folder the tab opened in
- **typing `launch`** brings the start screen up from anywhere, any time

**`q`, Esc or Ctrl-C on either screen leaves you at a normal prompt.** It is never stuck, and it
never exits the window.

## Failure behaviour

**The launcher must never stand between you and a shell.**

| Situation | Behaviour |
|---|---|
| fzf missing | numbered menu plus a one-time hint `brew install fzf` |
| bd missing | spaces still listed, counts show `(bd not installed)` |
| one space's bd fails or times out | that space shows `(bd unavailable)`; the others are unaffected |
| config missing or invalid | one-line message naming the file, then a shell |
| `new-session` fails | its own error is shown, then you are at a shell in `$HOME` |
| any unexpected error in `launch` | trapped: message, then a shell |

## Testing

- **`wb-backlog` and `wb-spaces` run against a fake `bd` on `PATH`**, in the style of the
  `program-overview.sh` tests (2026-10-15). Cases: normal JSON, `[]`, a non-zero exit, junk output,
  a hang past the timeout, a store with no `.beads`, ordering by wave, and in-progress marking.
  Plain bash test script, no framework.
- **`workbench.zsh`** gets each guard checked by running `zsh -i` with the relevant variable set.
- **A `◐` bead** checks both paths: its worktree exists (offer resume) and it doesn't (stale claim).
- **`launch` handoff** runs with `WORKBENCH_DRY_RUN=1`, so it prints the command it would run
  instead of running it. Tests drive fzf via `--filter`, or the fallback menu via stdin.
- **Acceptance is done by Tommy, by hand, in a real Terminal window, before anything is
  published:**
  1. A new window shows the summary.
  2. Acme → a NOW bead → an Acme worktree session starts on the Acme account, already briefed.
  3. Acme → something new → an exploratory worktree.
  4. A personal project → something new → Claude starts in that folder on the personal account.
  5. `q` gives a plain shell.
  6. VS Code's terminal and a new tab inside a worktree do not launch it.
  7. After Claude exits, the shell is in the session's folder.

## Publishing

- **The repo stays local** until acceptance passes. Then it is pushed to a **public**
  `tankermantate/workbench`. Public is deliberate: the second laptop can install it without
  signing in to a personal account.
- **Before the first push:** a check that no tracked file contains a real space name, path or email.
  It greps for the names in this machine's `spaces.toml`, matching whole words.
- **Commit authorship is public too.** This repo's commits so far carry the global git identity
  (a personal Gmail address). Before the first push, decide whether to set a repo-local
  `user.email` to the GitHub noreply address and rewrite the few local commits. Nothing is public
  yet, so the rewrite is free until then.

## Scope

**In (Project 1):** everything above.

**Out, and filed as separate beads:**
- **Project 2:** move `new-session` and `end-session` into workbench, with Acme's setup steps as a
  hook named in private config, so worktree sessions work for any space.
- **Project 3:** install on the second laptop; revive or retire the pre-1.0 personal bead stores.
- **Not planned:** a persistent side panel during a session, tmux, or any UI beyond the start screen.
