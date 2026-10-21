# Session scripts — worktree sessions for any space

**Status:** shipped · **Date:** 2026-10-18 · **Project 2 of 3** (bead wb-5jy;
see Scope in `2026-10-16-launcher-design.md`)

## Why

`new-session` and `end-session` live in `~/scripts` and only know one space. They find the repo by
trying two fixed paths, know one domain (`acme`) and one bead prefix (`acme-app-`), fix the project
folder in code, and carry that space's setup (`.env.local` link, `npm install`), its GitHub account
and its predeploy gate inline. A personal repo cannot get a worktree session at all, and the
launcher's `worktrees = true` only works for the one space the scripts were written for.

The goal: **any space with `worktrees = true` gets isolated worktree sessions**, and everything
specific to one space lives in that machine's private config, not in code.

What the user said:
- Worktree sessions are wanted for Acme **and some personal repos** in the coming months.
- Sessions are **started from the launcher**; `end-session` is still **typed by hand** (or run by
  Claude at the end of the work). Acme's protocol also tells people to type `new-session <id>`.
- Space-specific steps are **commands named in `spaces.toml`**, not scripts inside each repo and not
  fixed declarative fields.

## What you get

Two commands move into this repo, `bin/new-session` and `bin/end-session`. `install.sh` links them
into `~/.local/bin` like the other `bin/*` files. Both stay bash, as they are today.

### `new-session`

```
new-session <bead-id> [--space <key>] [--no-launch] [--safe]
new-session <space-key> [topic words…]  [--no-launch] [--safe]
```

| Shape | Branch | Worktree |
|---|---|---|
| bead id | `fix/<slug of title>` for a bug, `feat/<slug of title>` otherwise | `<dir>/<key>-<slug>` |
| space key, no topic | `explore/<YYYY-MM-DD-HHMMSS>` | same rule |
| space key + topic | `explore/<slug of topic>` | same rule |

`<dir>` is `$WB_WORKTREES_DIR`, default `~/.worktrees` (where existing worktrees already are). The
slug rules are today's: lowercase, non-alphanumerics to `-`, dashes collapsed, cut at 40 characters.

**Dropped:** the explicit form (`new-session acme feat/x --bead <id>`), `--type` and `--slug`. The
launcher never uses them.

**Which space.** A first argument that is a space key picks that space. Otherwise it is a bead id:
`--space <key>` names the space (the launcher always passes it); without it, `new-session` asks each
worktree space's bead store (`bd show <id> --json`, bounded by `WB_BD_TIMEOUT`) and takes the first,
in config order, that has the bead. Only a space's own store counts (a `.beads` between its root and
its repo top), because bd itself walks further up into stores that aren't the space's; `--space`
naming a space without one is an error. No bead-prefix configuration. Neither found: one error line
listing the space keys.

**Steps, in order:**
1. **Repo and project folder.** The repo is the git repo containing the space's `root`
   (`git rev-parse --show-toplevel`); the project folder is where `root` sits inside it
   (`--show-prefix`, empty at the repo top). `root` not in a git repo: error, nothing created.
2. **Pre-checks.** The worktree path already exists, or the branch is checked out in another
   worktree: error, exit 1, nothing created.
3. **Base.** If the repo has an `origin` remote: switch gh to `gh_account` if set (below), `git fetch
   origin`, best-effort `git pull --ff-only` of the main checkout (a failure is a note, as today),
   and branch from `origin/<default>`. **No `origin`:** no fetch; branch from local `<default>`.
   `<default>` is the **default branch**, found the same way by both scripts: `origin/HEAD`'s target
   when there is an `origin` that sets it, else `main` if that branch exists, else `master` if it
   exists, else the main checkout's current branch.
4. **Create** the worktree on the new branch.
5. **Beads link.** If the space has a bead store (the nearest `.beads` from `root` up to the repo
   top that holds bd's `config.yaml` or `metadata.json`; a `.beads` without them, such as old exports
   left in a subfolder, is skipped, as bd skips it), the worktree gets the matching `.beads` folder (mode 700, created if git
   didn't check one out) with a `redirect` file pointing back at the real store, using bd's relative
   path convention. Without it, bd in the worktree sees no database.
6. **`on_create`**, if set (below).
7. **Claim**, bead shape only: `bd update <id> --claim --append-notes "Branch: <branch> (worktree at
   <path>)"`. That note format is what the launcher reads to offer resuming a claimed bead. Append, not
   replace: `--notes` would erase the bead's existing notes. A failed claim is a warning; the session
   still starts.
8. **Banner**: space, worktree, branch, project folder, bead.
9. **`--no-launch`**: the last line is `WORKTREE_DIR=<worktree>/<project folder>`, and it exits 0.
   That is the launcher's contract today.
10. **Otherwise launch Claude** in the worktree's project folder: `CLAUDE_CONFIG_DIR` set from the
    space's `claude_config` for that one command (removed when unset), and
    `--dangerously-skip-permissions` unless the space is `safe` or `--safe` was given. Inside a
    Claude session, or without a terminal, it prints the `cd` + `claude` line to run instead and
    exits 0 (today's nested-session guard).

### `end-session`

```
end-session [<worktree-path>] [--force] [--base=<branch>]
```

Kept from today: default target is the current worktree; it refuses the main checkout and anything
that isn't a registered worktree; it refuses a dirty tree, and with an `origin` it refuses commits
that aren't pushed; all of that is skipped when nothing is at risk (every commit already on the base
branch); `--force` bypasses the checks and keeps the branch; a branch merged into the base (local or
`origin/`) is deleted after the worktree is removed, otherwise kept with the command to delete it.

Changed:
- **Main checkout** comes from the worktree itself (`git rev-parse --git-common-dir`), not from fixed
  paths.
- **Which space**: a space with `worktrees = true` whose repo is this worktree's repo — the one
  whose key starts the worktree's folder name (`<key>-<slug>`, as `new-session` names it), else the
  first such space in `spaces.toml`. Spaces without `worktrees = true` never count, so one on the
  same repo can't hide another space's `before_end`.
- **It fails closed**, because `before_end` replaces a check that used to be hard-coded:
  - **The config can't be read** (`wb-spaces` exits non-zero: no file, an invalid file, or a broken
    `python3`): `end-session` refuses with the reason, unless `--force` is given.
  - **No space matches** (for example the space's root folder moved, so `wb-spaces` skipped it): it
    goes ahead, but first prints `end-session: no space in spaces.toml claims <repo>; no before_end
    check ran.` on stderr, so a missing gate is never silent.
- **`--base`** defaults to the repo's default branch, found exactly as `new-session` finds it, so a
  `master` repo's branches are recognised as merged.
- **No `origin`**: no fetch and no unpushed check. "Nothing at risk" means every commit is on local
  `<base>`. An unmerged branch is kept, so no work is lost.
- **`before_end`** replaces the hard-coded predeploy gate (below).

## Configuration

Three new optional fields on a `[[space]]`, used only with `worktrees = true`. A personal repo
leaves all three out.

| Field | When | On failure |
|---|---|---|
| `gh_account` | before `git fetch`: if `gh auth status --active` shows another account, `gh auth switch --user <it>` | a warning (gh missing or the switch failed); the fetch is still tried, as today |
| `on_create` | `new-session` step 6, in the new worktree's project folder | `new-session` stops with exit 1 and the hook's output. The worktree stays; the message gives `end-session --force <path>` to remove it. The bead is not claimed. |
| `before_end` | `end-session`, only when something is at risk and `--force` wasn't given, in the worktree's project folder | `end-session` refuses with exit 1, shows the hook's output, keeps the worktree |

Hooks are strings run with `sh -c`, so `~/…` and `$VAR` work. They come from the user's own
private config and are trusted like `~/.zshrc`. **A hook is one line:** `wb-spaces` rejects a hook
containing a newline (exit 4), because its TSV output would turn the newline into a space and
quietly run a different command. Anything longer goes in a script the hook names. Variables set for
every hook:

| Variable | Value |
|---|---|
| `WB_SPACE` | the space key |
| `WB_WORKTREE` | the worktree's top folder |
| `WB_PROJECT` | the project folder inside the worktree |
| `WB_SOURCE` | the project folder in the main checkout (where untracked files such as `.env.local` live) |
| `WB_BRANCH` | the branch |
| `WB_BEAD` | the bead id; empty for exploratory sessions, and always empty in `before_end` (`end-session` doesn't know which bead a worktree served) |
| `WB_SHA` | `before_end` only: the worktree's `HEAD` |

Other config changes:
- **`session_cmd` becomes optional.** Default: workbench's own `new-session` by absolute path
  (`$WORKBENCH_HOME/bin/new-session`), not a `PATH` lookup, so a stale `new-session` earlier on
  `PATH` can't be picked up instead. The launcher's tests
  keep using it to plug in a fake. The launcher now passes `--space <key>` with a bead id, so any
  `session_cmd` must accept it.
- **Space keys.** Each worktree space needs a unique key. A `root` space must set `space_key`. In a
  `glob` space each folder's key is its folder name, unless the space sets `space_key` (then all its
  folders would share one key, which is an error). Duplicate keys are a config error (exit 4).
- `wb-spaces` prints three more columns at the end of each row: `gh_account`, `on_create`,
  `before_end` (`-` when unset). Existing columns keep their positions.

### This machine's Acme space, after cutover

The private hook `~/.config/workbench/hooks/acme-setup` holds today's `setup_acme`: symlink
`$WB_SOURCE/.env.local` into `$WB_PROJECT`, then `npm install --no-audit --no-fund --silent` there
(a real `node_modules`, because Turbopack rejects a symlinked one). The space gains:

```toml
gh_account = "<the GitHub account that can see the repo>"
on_create  = "~/.config/workbench/hooks/acme-setup"
before_end = 'test -f ~/.local/state/acme-predeploy/$WB_SHA || { echo "predeploy has not passed for $WB_SHA; run: acme-predeploy"; exit 1; }'
```

`acme-predeploy` itself stays in `~/scripts`; only the check of its marker moves into config.

## Failure behaviour

| Situation | Result |
|---|---|
| unknown space key or bead in no store | one error line listing the space keys; exit 2; nothing created |
| `root` not in a git repo | error; exit 2; nothing created |
| worktree path exists / branch checked out elsewhere | error; exit 1; nothing created |
| `git fetch` fails | error; exit 1; nothing created |
| `on_create` fails | exit 1; worktree kept; message names `end-session --force <path>`; bead not claimed |
| claim fails | warning; session continues |
| Ctrl-C during `new-session` from the launcher | the launcher's existing message (half-made worktree, `git worktree list`) |
| `before_end` fails | `end-session` refuses; worktree kept |
| `end-session` can't read the config | refuses with the reason; `--force` overrides |
| `end-session` on a worktree no space claims | works, and says on stderr that no `before_end` ran |

## Testing

Plain bash under `tests/`, like the rest, with the same `lib.sh`. Throwaway repos with a bare
`origin`, `WB_WORKTREES_DIR` and `WORKBENCH_CONFIG` pointing into the test's temp folder, and fakes
for `bd` and `gh`. Nothing touches `~/.worktrees` or the real config.

- `test_end_session.sh`: the ten cases of today's `~/scripts/test-end-session.sh` (the acme predeploy
  cases become a `before_end` hook), plus: no-`origin` repo, `before_end` sees the right `WB_*`
  values, a worktree no space claims (goes ahead, with the warning), an unreadable config (refused,
  and allowed with `--force`), a `master` repo (base found, merged branch deleted).
- `test_new_session.sh`: bead shape (branch from title, bug → `fix/`), space + topic, space with no
  topic, `--space`, finding the space from the stores, unknown id, a repo with no `origin`, a project
  folder below the repo top, the beads redirect, `on_create` variables and failure, the gh switch
  (and gh missing), `--append-notes` claim, `--no-launch` last line, `safe`/`--safe`, the nested
  guard.
- `test_wb_spaces.sh`: the new columns, optional `session_cmd` (default is the absolute workbench
  path), glob keys from folder names, duplicate keys rejected, a hook with a newline rejected.
- The launcher's existing tests keep passing, with the fake `new-session` accepting `--space`.

## Cutover: one sitting, straight after the merge (with the user's OK at that point)

**Why one sitting:** the Acme space today sets `session_cmd = "new-session"`, which reaches
`~/scripts/new-session` through `~/.local/bin`. That old script rejects unknown flags, so once the
merged launcher passes `--space`, every Acme bead picked in the launcher fails until these steps are
done. Run them together, right after merging, before opening a new Terminal window:

1. In the Acme space: **delete `session_cmd`** (otherwise the explicit name still wins over the new
   default), and add `gh_account`, `on_create` and `before_end`. Write
   `~/.config/workbench/hooks/acme-setup`.
2. `~/.local/bin/new-session` and `end-session` are links to `~/scripts`; `install.sh` skips files it
   didn't create. Remove those two links, then rerun `./install.sh`.
3. Check: `new-session --help` and `end-session --help` come from workbench, and a launcher pick of
   an Acme bead reaches `npm install`.

Afterwards:
- Existing worktrees in `~/.worktrees` keep working: the new `end-session` finds their space by
  repo.
- `~/scripts/new-session`, `end-session` and `test-end-session.sh` stay until the user deletes them.

## Acceptance

1. An Acme bead started from the launcher behaves as today: worktree, `.env.local` link,
   `npm install`, claim note, Claude on the Acme account.
2. `end-session` on an Acme worktree with unmerged work still refuses until predeploy has passed.
3. A personal repo with `worktrees = true` and no hooks gets a worktree session from the launcher,
   and `end-session` removes it.
4. `scripts/check-leaks.sh` finds no new private names in code or tests.

## Scope

**In:** the above.

**Out:** the second laptop and its accounts (Project 3); moving `acme-predeploy` into workbench;
hooks inside repos; any new way of starting sessions beyond the launcher and the two command forms.
