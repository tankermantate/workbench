# workbench

A start screen for every Terminal window. Open a window or a tab and you're in it: every space's
backlog, a choice of existing work or something new, and Claude Code starting in the right folder,
on the right account, already briefed.

```
Terminal opens
  → Space?  each space, with its bead counts         (esc: plain shell)
  → Work?   ✦ something new | that space's beads     (type to search)
  → Claude starts there, with an opening prompt
```

## Install

Needs macOS with zsh, `python3` 3.11 or later, `git`, and [bd](https://github.com/gastownhall/beads).
[fzf](https://github.com/junegunn/fzf) is optional; without it the launcher shows a numbered menu.

```bash
./install.sh                     # links bin/* into ~/.local/bin; prints the ~/.zshrc line
cp spaces.example.toml ~/.config/workbench/spaces.toml   # then edit it
```

Add the line `install.sh` prints to the **end** of `~/.zshrc`. Re-running `install.sh` is safe.

## Daily use

- **New window or tab:** the launcher opens by itself. Pick a space, then a bead or
  `✦ something new`.
- **esc:** a plain shell, in the folder the tab opened in (q in the numbered menu).
- **`launch`:** brings the launcher back from any shell.
- **A bead already claimed in a worktree:** the launcher offers to resume it there
  (`claude --continue`).
- **Labels the work screen reads:** `wave:1` and `wave:2` put a bead under NOW and NEXT;
  `icebox` puts it in a last section and out of the open count, whatever its wave. A claimed bead
  untouched for over 7 days shows `idle 23d`, so a forgotten session stands out.

It stays closed inside Claude, in a nested shell, in an IDE's terminal (only Apple Terminal and
terminals listed in `[launcher].terminals` count), and when `WORKBENCH_NO_LAUNCH=1` is set.

## Worktree sessions

A space with `worktrees = true` gives each piece of work its own git worktree and branch, in
`~/.worktrees/` (`WB_WORKTREES_DIR` overrides). The launcher does this for you; the commands also work by hand:

```bash
new-session <bead-id>              # worktree named after the bead; claims it in bd
new-session <space-key> [topic]    # no bead: worktree named after the topic
end-session [<worktree>]           # remove it, once the work is merged or pushed
```

`new-session` fetches, branches from the default branch, points the worktree at the space's bead
store, runs the space's `on_create` hook, claims the bead and starts Claude.

`end-session` refuses while the worktree has uncommitted or unpushed work, while the space's
`before_end` hook fails, or when no space in your config claims the repo (`--no-space` goes ahead
anyway). `--force` skips those checks and keeps the branch. A merged branch is deleted; an
unmerged one is kept. Either way it appends a note to the session's bead saying what happened,
without closing it: merged isn't the same as done.

## While you work

A session the launcher (or `new-session`) starts knows which bead it's on:

- **Your status line can show it.** `wb-statusline-bead` reads the status line's JSON on stdin and
  prints `◆ x1y <title>`, `✓ x1y done · close this session`, `◇ no bead`, or nothing outside a
  workbench session. Call it from your own status line script:

  ```bash
  input=$(cat)
  bead=$(printf '%s' "$input" | wb-statusline-bead)
  printf '%s %s\n' "$bead" "$the_rest_of_your_line"
  ```

  With no status line of your own, point `statusLine` in your Claude settings at
  `wb-statusline-bead` directly.
- **Claude gets the goal back after compaction or resume:** the bead's title, description and
  acceptance criteria.
- **`✦ something new` picks up its bead.** The first bead Claude claims in the session becomes the
  session's bead.
- **Claiming a second bead asks first.** Claude asks whether to continue in this session or start
  fresh. Start fresh puts the bead back to open, for you to start from the launcher in a new tab.
- **Closing the bead ends the session's job.** Claude finishes the close-out (`end-session` in a
  worktree space), then tells you to `/exit` and start the next bead fresh.
- **`wb-focus`** prints this session's bead. Inside Claude, `wb-focus <id>` moves the session to
  another bead, and `wb-focus --clear` drops it.

After pulling a new workbench, rerun `./install.sh` so new commands like these are linked onto your PATH.

All of this comes from hooks passed with `claude --settings` at launch. A `claude` you start by
hand is unchanged, and nothing is written into your repos or `~/.claude`. Those hooks, and the
record of which session is on which bead, live in `~/.cache/workbench/`.

## Configuration

Everything about your machine lives in `~/.config/workbench/spaces.toml` (or `$WORKBENCH_CONFIG`),
never in this repo. `spaces.example.toml` documents every key. In short:

| Key | Meaning |
|---|---|
| `name`, `root` | A space and its folder. `glob` instead of `root` makes one space per folder. |
| `beads` | `true`, `false` or `"if-present"`. |
| `worktrees`, `space_key` | Sessions get their own worktree; `new-session <key>` names the space. |
| `claude_config` | A non-default Claude profile (`CLAUDE_CONFIG_DIR`) for this space. |
| `protocol` | A file every session in this space reads first. |
| `safe` | Keep Claude's permission prompts on. |
| `gh_account` | The `gh` account to switch to before fetching. |
| `on_create`, `before_end` | Hooks: one-line shell commands, run in the worktree with `WB_SPACE`, `WB_WORKTREE`, `WB_PROJECT`, `WB_SOURCE`, `WB_BRANCH`, `WB_BEAD` set, and `WB_SHA` for `before_end`. Keep private setup scripts in `~/.config/workbench/hooks/`. |

## Development

```bash
tests/run.sh             # every test; plain bash, with fake bd, gh and claude
scripts/check-leaks.sh   # before any push: no private names in files or history
```

Designs and plans are in `docs/specs/` and `docs/plans/`.
