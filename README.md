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

## What you need

workbench is a launcher around tools you install and sign in to yourself. It holds no keys and
calls no AI service directly: every Claude session it starts is your own `claude`, on your own
account, using your own plan or API credits.

| You need | Why | Get it |
|---|---|---|
| macOS, with zsh as your shell | The launcher is a zsh script; tab handling uses Apple Terminal (other terminals: see `[launcher].terminals`). | zsh is the macOS default. |
| [Claude Code](https://docs.claude.com/en/docs/claude-code), signed in | Every session the launcher starts is `claude`. | Install it, run `claude` once and log in. |
| [bd (beads)](https://github.com/gastownhall/beads) | The issue tracker: each space's backlog, the beads you pick, the beads sessions close. | `wb-setup` installs it (`brew install beads`) and runs `bd init` in the projects you choose. beads shares anonymous usage metrics; `bd metrics off` stops that. |
| `python3` 3.11 or later | The helper commands are Python. | `brew install python` if `python3 --version` is older (`wb-setup` offers it). |
| `git` | Worktree sessions, and fetching before they start. | Comes with the Xcode command line tools. |
| [fzf](https://github.com/junegunn/fzf) (optional) | Searchable screens. Without it, the launcher shows a numbered menu. | `brew install fzf` |
| [gh](https://cli.github.com) (optional) | Only if a space sets `gh_account`. | `brew install gh` |

## Set up

Install Claude Code and sign in first (run `claude` once). Then, about ten minutes:

```bash
git clone https://github.com/tankermantate/workbench.git ~/dev/workbench
~/dev/workbench/bin/wb-setup
```

`wb-setup` walks you through the rest, asking before each change:

1. **Tools.** It checks python 3.11+, git, Claude Code and beads, and offers to install beads,
   fzf or a newer python with Homebrew.
2. **Commands.** It runs `install.sh`, which links the commands into `~/.local/bin` and, if you
   say yes, schedules the background jobs (see [What runs on its own](#what-runs-on-its-own)).
3. **Spaces.** It asks for your project folders, one at a time, and writes
   `~/.config/workbench/spaces.toml`. A space is a project folder (or a folder of projects) the
   launcher offers. For a git repository it asks whether each task should get its own
   [worktree](#worktree-sessions); for a folder with no backlog it offers `bd init`, which adds a
   `.beads` folder, notes telling Claude about it and git hooks, and commits them. It also offers
   a **Demo** space with three sample tasks to try the launcher on (in
   `~/.local/share/workbench/demo`; delete its `[[space]]` and that folder to remove it).
4. **Terminal.** It adds the launcher line to the end of `~/.zshrc` (and `~/.local/bin` to your
   `PATH` if it isn't there).
5. **Claude Desktop.** When this version has `wb-mcp`, it offers to connect the Claude Desktop
   app, so you can plan with your tasks in a chat.

It ends by running `wb-doctor`. Then open a new Terminal window: the launcher appears. Pick a
space, then a bead or `✦ something new`, and Claude starts in that folder. Run `wb-setup` again
to add projects (it never overwrites `spaces.toml`, and skips what's done); edit `spaces.toml`
by hand for everything else: `spaces.example.toml` documents every key.

**`wb-doctor`** checks the setup any time: one line per check, `!!` for what to fix and how,
`--` for optional things. If the launcher doesn't appear, run it, or `launch`.

Optional, once the basics work: a status line showing the session's bead and space, and a bell on
the tab that needs you (see [While you work](#while-you-work)); planning rituals (see
[Planning rituals](#planning-rituals)).

<details>
<summary>Setting up by hand instead</summary>

Run `./install.sh` (or `./install.sh --no-schedule`) in the clone and add the `source …/workbench.zsh`
line it prints to the end of `~/.zshrc`. Copy `spaces.example.toml` to
`~/.config/workbench/spaces.toml`; the least that works is a name and a folder per space:

```toml
[[space]]
name  = "My app"
root  = "~/dev/my-app"
beads = true
```

Then run `bd init` in each space's folder, and `wb-doctor` to check.
</details>

### What runs on its own

`./install.sh` adds two macOS launch agents (skip both with `--no-schedule`):

- **A session snapshot every 10 minutes** (`wb-restore save`), so you can bring your sessions back
  after a restart. It only reads which sessions are open: no Claude usage.
- **Weekly grooming, Saturdays at 06:00** (`wb-groom run --all`). For each space that has a plan
  (you create one with `wb-groom strategy <space>`), it runs `claude -p` once to judge that space's
  backlog. **This uses your Claude account's usage**, on that space's Claude profile. With no plans
  set up, it grooms nothing and uses nothing.

The launcher also looks for **a new version**, at most once a day: in the background it asks the
repo you cloned from (GitHub) for its release tags (`git ls-remote`), with a 5-second timeout,
and says nothing if that fails. Nothing about you or your spaces is sent. When a newer release
is out, its first screen says `workbench 0.2 available: wb-update`. Turn the look off with
`update_check = false` under `[launcher]` in `spaces.toml`.

### Updating

`wb-update` brings you to the latest version: it pulls (fast-forward only), re-runs
`install.sh` (keeping the schedule if you installed it) and shows what changed since your
version, from `CHANGELOG.md`. It refuses, changing nothing, when your checkout has local
changes or isn't on a branch. `wb-update --version` prints the installed version.

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
- **Start here:** beads flagged `attention` (due soon, or neglected and protected) come first, up to five then `+N more need attention`, shown even in a short backlog; a long backlog then opens with its top three ready beads and why each was picked
  (a fresh claim, NOW/NEXT, priority, a "Done when" line, what it unblocks), then how many beads
  were created and closed in the last 30 days.

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
- **It can show which space you're in, too.** `wb-statusline-space` reads the same JSON and prints
  the space's name as the launcher shows it (`Acme`), `Acme ⑂ worktree` in one of its worktrees,
  or `(folder)` where no space claims the folder. It goes by the folder Claude started in, so a
  tool's `cd` doesn't move it, and it finds a worktree's space the way `end-session` does. Put it
  first on the line when you work across several spaces:

  ```bash
  space=$(printf '%s' "$input" | wb-statusline-space)
  ```

  Give a space a `color` and it's easy to spot in a row of terminal tabs. `--json` hands back
  the parts (`label`, `space`, `worktree`, `color`, `emoji`), so your script can title the tab
  with the colour's circle first:

  ```bash
  sp=$(printf '%s' "$input" | wb-statusline-space --json)
  tab="$(jq -r '"\(.emoji) \(.label)" | ltrimstr(" ")' <<< "$sp") · $task"   # 🟣 Acme · x1y fix
  printf '\033]1;%s\007' "$tab" > /dev/tty
  ```
- **Claude gets the goal back after compaction or resume:** the bead's title, description and
  acceptance criteria.
- **`✦ something new` picks up its bead.** The first bead Claude claims in the session becomes the
  session's bead.
- **Claiming a second bead asks first.** Claude asks whether to continue in this session or start
  fresh. Start fresh puts the bead back to open, for you to start from the launcher in a new tab.
- **Closing the bead ends the session's job.** Claude finishes the close-out (`end-session` in a
  worktree space), then tells you to `/exit` and start the next bead fresh.
- **`wb-tabs`** shows every open terminal tab, grouped by what it needs from you: waiting on you
  (`blocked` on a prompt, or `your turn` with its bead still open, each with its goal and next
  step), working, and nothing pending. Plain shells and sessions with no bead are labelled, not
  dropped. It only reads, in about a second; a bead store that doesn't answer within 2s
  (`WB_TABS_BD_TIMEOUT`) says so on its rows. The launcher's first screen has it too, as
  `✦ open tabs`, where it's a list: Enter or a double-click goes to that tab (Apple Terminal), and esc brings you back. That screen also shows a yellow
  `N waiting on you` on each space and in total.
- **A bell on the tab that needs you:** add `"preferredNotifChannel": "terminal_bell"` to
  `settings.json` in each Claude config dir. Claude Code then rings the terminal bell when a session
  finishes or pauses for permission while you're away, and Apple Terminal shows it on that tab.
- **Restarting without losing your tabs.** `wb-restore save` records every open Claude session
  (its folder, account and session id, and its space and bead); `install.sh` also runs it every 10
  minutes, so a crash is covered too. After the restart, the first new tab asks
  `11 sessions were open before the restart. Bring them back? [Y/n]` (answer no and it doesn't ask
  again until the next restart), or run `wb-restore` yourself: it takes the newest snapshot from before the boot, leaves out sessions still open and
  folders that are gone, lets you untick any you're done with, then opens one Terminal window per
  session. Each new window resumes its session (`claude --resume`) on the same account and bead,
  instead of showing the launcher. Allow Terminal under System Settings > Privacy & Security >
  Automation the first time. Snapshots older than 7 days are pruned; they live in
  `~/.local/state/workbench/restore/`.
- **When to restart.** The launcher's screens show `up 162 days · swap 41 GB on 32 GB RAM`, in
  yellow with `restart soon` once the Mac has been up 30 days or swap reaches half of RAM, which
  is when it starts to grind. `wb-health` prints the same line.
- **Tidying finished worktrees.** `wb-tidy` lists every worktree with whether it's finished:
  merged into the default branch, nothing uncommitted, no Claude session open in it, and its bead
  closed. It offers only those, all ticked; Enter runs `end-session` on each, one at a time,
  stopping at the first refusal. Anything else is listed with why it stays. A worktree no bead
  names stays too; `wb-tidy --no-bead` offers those as well, when merged and clean.
- **`wb-focus`** prints this session's bead. Inside Claude, `wb-focus <id>` moves the session to
  another bead, and `wb-focus --clear` drops it.

After pulling a new workbench, rerun `./install.sh` so new commands like these are linked onto your PATH.

All of this comes from hooks passed with `claude --settings` at launch. A `claude` you start by
hand is unchanged, and nothing is written into your repos or `~/.claude`. Those hooks, and the
record of which session is on which bead, live in `~/.cache/workbench/`.

## Planning rituals

Three rituals keep a space's backlog pointed at what matters. A space takes part once it has a
**plan directory**, `~/.config/workbench/plans/<space>/` (`$WB_PLANS_DIR`), which is private and never
in this repo: `goals.md` (3-5 goals, a `date: YYYY-MM-DD` line, optional `sprint: now=5 next=8`),
`protected.md` (a `labels:` line plus words for judgement), `calendar.md` (dated obligations) and
`sources.md` (what else to read).

| When | What | Who |
|---|---|---|
| Saturday 06:00 | **Grooming**: a read-only Claude judges the backlog against the plan. `wb-groom` applies what policy allows (sprint labels, icebox of unprotected beads, `attention` flags) and leaves the rest as proposals. | launchd, unattended (`wb-groom run --all`, log in `~/.local/state/workbench/groom/launchd.log`) |
| Next time you open the launcher | **Review**: screen 1 shows `groomed Sat · review` (`groomed Sat · partial · review` when the judge did not show it read the whole backlog, so nothing was applied unattended; or `grooming missed Oct 24, see launchd.log` when a Saturday run left nothing to review, or `grooming failed Sat, see summary` when the newest run stopped with nothing applied; `grooming failed Sat: Claude login expired, log in again` when the fix is a fresh login on the space's Claude account); the work screen has `✦ review Saturday's grooming`. Claude walks the summary with you and applies what you accept. | you, with Claude |
| Monthly, or when the plan is 30+ days old | **Strategy**: screen 1 shows `strategy due`; Claude prepares from the month's closes and what you reversed, and rewrites the plan with you. | you, with Claude |

A plan whose `goals.md` has no date or is over 45 days old, or that has no `protected.md`, counts as missing or stale and fails closed: grooming still runs, but
applies nothing and its summary leads with "strategy session needed".

Each run is a folder, `~/.local/state/workbench/groom/<space>/<YYYYMMDD-HHMM>/` (`$WB_GROOM_DIR`), holding
`summary.md` (read this first), the judge's `decisions.json`, and a record of every change
(`before.jsonl`, `applied.jsonl`). Finishing a review writes a `reviewed` file there.

```bash
wb-groom strategy <space>     # start a space: makes the plan dir from templates, prints its path
wb-groom run <space>          # groom one space now (or --all)
wb-groom undo <run dir> [id]  # put beads back exactly as they were; refuses one changed since
wb-groom apply <run dir> <space root> --plan <plan dir> --proposal <n>   # one proposal (review does this)
```

Fresh template plans carry `date: YYYY-MM-DD` on purpose: until the first strategy session sets a
real date, the plan counts as missing.

## Plan in Claude Desktop

Talk your plans through in the Claude Desktop app, against your real beads: ask what's in an epic,
split it into tasks, sharpen a description, and the changes are in the launcher next time you open it.

```bash
wb-mcp connect      # quit Claude Desktop first; then open it again
wb-mcp check        # which spaces Desktop can see, and whether it's connected
wb-mcp disconnect   # take it out again
```

Desktop sees only the spaces of the account it's signed in as: a space belongs to the account its
`claude_config` is logged in to (`~/.claude.json` without one). Sign Desktop in to another account
and it sees that account's spaces instead. Claude can file, refine and link beads there; it can't
close, claim or defer them, can't change grooming's labels (`wave:1`, `wave:2`, `icebox`,
`attention`), and can't lower a protected bead's priority. Spec:
`docs/specs/2026-11-17-plan-in-claude-design.md`.

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
| `color` | `red`, `orange`, `yellow`, `green`, `blue`, `purple` or `brown`: the space's colour in tab titles and the status line (see `wb-statusline-space`). |
| `folder_colors` | A glob space only: colours for some of its folders, like `{ alpha = "red" }`; the rest keep its `color`. |
| `[launcher]` `update_check` | `false`: never look for a new version (see [What runs on its own](#what-runs-on-its-own)). |
| `judge_env` | Variables the grooming judge needs beyond its allowlist (a proxy, Bedrock), with their values. |
| `gh_account` | The `gh` account to switch to before fetching. |
| `on_create`, `before_end` | Hooks: one-line shell commands, run in the worktree with `WB_SPACE`, `WB_WORKTREE`, `WB_PROJECT`, `WB_SOURCE`, `WB_BRANCH`, `WB_BEAD` set, and `WB_SHA` for `before_end`. Keep private setup scripts in `~/.config/workbench/hooks/`. |
| `after_end` | Hook run by `end-session` right after the worktree is removed, on every path including `--force`, in the main checkout's project folder (the worktree is gone), with the same variables. For cleanup outside the folder. A failure or a 60 s hang only warns. |

## Development

```bash
tests/run.sh             # every test; plain bash, with fake bd, gh and claude
scripts/check-leaks.sh   # before any push: no private names in files, history or the bead db
```

Changes go through pull requests: work on a branch (the launcher gives each session its own
worktree), push it and open a pull request. GitHub runs `tests/run.sh` on macOS for every pull
request, and `main` only takes a merge with green tests.

Releasing: in a pull request, bump `VERSION` (`X.Y`) and add a `## X.Y — <date>` section to the top
of `CHANGELOG.md` saying what changed for users (a test keeps the two in step). Once it's merged,
tag the merge and push the tag: `git tag vX.Y <sha> && git push origin vX.Y`. Within a day every
launcher on an older version shows the notice.

Designs and plans are in `docs/specs/` and `docs/plans/`.

## License

MIT. See `LICENSE`.
