# Guided setup (wb-setup) and the health check (wb-doctor)

Vision gap 4: setting up meant cloning, running `install.sh`, copying and hand-editing
`spaces.toml`, running `bd init` in each project and pasting a line into `~/.zshrc`. The vision
promises about ten minutes, guided, once Claude Code is installed.

## The flow

`wb-setup`, run from the clone (`~/dev/workbench/bin/wb-setup`), goes step by step. Enter takes the
`[default]`; each step skips what is already done, so running it again is how you add projects.
Answers come one per line on stdin, so the tests drive it without a terminal.

1. **Tools.** python3 3.11+, git, `claude`, `bd`, fzf. Homebrew is offered for python, beads and
   fzf (with `HOMEBREW_NO_AUTOREMOVE=1`: brew's autoremove has removed a dependency-only python
   before). Missing git or Claude Code stops setup with where to get it; it installs neither.
   fzf is optional.
2. **Commands.** When `~/.local/bin/wb-spaces` isn't linked to a workbench checkout, it runs
   `install.sh`, asking first whether to schedule the background jobs (`--no-schedule` if not).
   `install.sh`'s output shows only when it fails.
3. **Spaces.** With no `spaces.toml`, it asks for project folders one at a time: the folder,
   a name (the folder's name by default; taken names are asked again), whether to use a
   worktree per task (asked only in a git repository; the space key is the name, slugged and
   made unique), and `bd init` when the folder has no store (found the way bd finds it, walking
   up the repository: `wb_session.store_root`). The `bd init` question says what it does to the
   project: a `.beads` folder, AGENTS.md and CLAUDE.md notes, git hooks, a commit, and a
   `git init` if the folder isn't a repository. It runs with `--non-interactive`; its output
   shows only when it fails, except bd's anonymous-metrics notice, which setup restates once
   with how to opt out. Declining `bd init` writes `beads = "if-present"`. So does a repository with staged changes:
   bd's commit would sweep them in (checked against bd 1.1.0), so setup doesn't offer `bd init`
   there and says how to run it once they're committed or unstaged.
   With a `spaces.toml`, it asks whether to add a project; it never rewrites what's there.
4. **Demo.** Unless a space is called Demo, it offers one: `~/.local/share/workbench/demo`
   (`WB_DEMO_DIR`), `bd init -p demo` and three sample tasks that walk through picking a task,
   something new and `wb-tabs`. A demo folder that already has a store is reused, not reseeded.
5. **Writing the config.** New spaces are appended (a new file gets a header pointing at
   `spaces.example.toml` and an empty `[launcher]`). Strings are written as JSON strings, which
   are TOML basic strings; folders under home are written with `~`. The result is read back
   through `wb-spaces`; if it doesn't read, the file goes back to what it was (fail closed).
6. **Terminal.** It offers to append the `source …/shell/workbench.zsh` line to `~/.zshrc`
   (`ZDOTDIR` honoured) and, when the bin dir isn't on `PATH` and `~/.zshrc` doesn't already add
   it, an `export PATH` line. `install.sh` itself still never edits `~/.zshrc`.
7. **Claude Desktop.** When this checkout has `bin/wb-mcp` (vision gap 1, `WB_MCP`), it offers
   `wb-mcp connect` unless Desktop's config already has the `workbench` server; a failure is a
   note, not a stop. Without wb-mcp it says planning in Claude isn't in this version yet.

Then it runs the doctor and exits with its code. ctrl-c or the end of stdin stops with
`stopped; run wb-setup again to carry on` and exit 1.

`install.sh` points a first install (no `spaces.toml`) at `wb-setup`; `wb-spaces`' missing-config
message says `run wb-setup to make one`.

## wb-doctor

One line per check: `ok`, `--` (optional, or a note) and `!!` (to fix, with how); exit 1 when
any line is `!!`.

| Check | `!!` when | `--` when |
|---|---|---|
| python3 (`WB_PYTHON`) | missing or older than 3.11 | |
| git, claude, bd | missing (bd: or `bd version` fails) | |
| fzf | | missing |
| commands | `wb-spaces` in the bin dir isn't linked to a workbench checkout | the bin dir isn't on `PATH` and `~/.zshrc` doesn't add it |
| `~/.zshrc` | no line sourcing a `shell/workbench.zsh` | |
| schedule | | either launch agent's plist is missing |
| `spaces.toml` | missing, or `wb-spaces` can't read it (its reason) | |
| each space | its root isn't a folder; `beads = true` with no store; `worktrees = true` outside a git repository | |
| Claude Desktop | | wb-mcp isn't in this version, or it isn't connected |

Any checkout counts for the links and the `~/.zshrc` line, so the doctor run from a worktree
doesn't fail on the main checkout's install. bd's version isn't pinned: a new user gets
Homebrew's current beads.

## Python 3.9

`wb-setup`, `wb-doctor` and `lib/wb_doctor.py` avoid `tomllib` and 3.10+ syntax: macOS's own
`/usr/bin/python3` is 3.9, and saying that python is too old is part of their job. They read
the config only through `wb-spaces`, which runs on the python 3.11+ found on `PATH`.

## Not done here

- Installing Claude Code or Homebrew: setup says where to get them.
- Connecting Claude Desktop needs wb-mcp (gap 1); until that ships, step 7 is a note.
- Glob spaces (a folder of projects): setup writes one space per folder; `spaces.example.toml`
  shows the glob form for hand-editing.
