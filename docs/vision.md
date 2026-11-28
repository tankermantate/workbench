# Workbench vision

**Status: working-backwards draft, November 2026.** The press release and FAQ below describe
workbench on the day the vision ships, written now so the roadmap has something to answer to.
They are not a description of today. [What works today](#what-works-today) and the
[gap table](#gaps-between-this-vision-and-today) say plainly what exists, what is partly there,
and what is not built yet. When a gap closes, its row changes; when the vision changes, this file
changes first.

---

## Press release

### Workbench: always know where you are, however much you have going on

*An open-source workbench for people who build with AI across many streams at once: a roadmap
you shape in conversation with Claude, a terminal that opens on the work that matters, and
sessions that never lose their place.*

**[Launch date to be set]** — AI made starting work almost free, and work multiplies at every
level. One idea becomes a list of tasks, and then too many tasks. The tasks get tracked, and then
there are too many of those. Sessions open, some tied to a task and some not, and then more
sessions than you can hold in your head. Above them sit projects, initiatives and whole areas of
your life, and for many people several personas: a day job, a side business, family. Each level
splits into more of the level below. The building got easy. Staying oriented did not: by
Thursday nobody, including you, can say what is in flight, where it is, and what should come
next.

Workbench keeps you oriented at every level. It starts where the mess is worst, with sessions:
every session it starts is tied to a task, knows what done looks like, and can be found, resumed
or closed out. From there it works upwards. You think and plan in Claude, where Claude is best:
you see your roadmap and brainstorm against it ("split this into smaller pieces", "what has to
happen before launch?", "write the done-when for these three"). What you agree on lands as real
tasks, the same ones your build sessions use, with nothing to copy across. Then you build in
Claude Code, where Claude is best at building: every new terminal opens on your projects and the
tasks that are ready, you pick one, and Claude starts in the right folder, already told which
task it's on and what done looks like. As you work, progress flows back to the roadmap you see
in Claude: it is the same task store, so when a task closes, the roadmap already shows it.

Workbench works the same way in each of your Claude personas. Sign in as your work self and it
helps you there; sign in as your personal self and it helps you there. Each persona keeps its own
roadmap, and nothing crosses between them.

Workbench brings the habits good product teams rely on without making you follow a process.
Work you start from workbench starts as a task, so nothing is in flight without a reason. New
ideas get shaped before any code is written. Each task gets its own workspace, finished work is
closed out cleanly, and a weekly review checks the backlog against your goals. It suggests rather
than insists: press escape and you have a plain terminal. The one thing it will not do is throw
away work.

"I'm a product manager. My job is keeping many streams moving without dropping any of them, and
AI made me able to build in all of them at once," said the creator of workbench. "Every level
kept splitting: tasks into more tasks, sessions into more sessions, projects into more projects,
across three different Claude personas. What I was missing was something that keeps me oriented
at every level, so I always know where I am and what's next. Claude is a brilliant thinking
partner and Claude Code is a brilliant builder. Workbench is what lets them work as one team,
with me as the product owner instead of the person trying to remember everything."

**How it works**

- **One map per persona.** Your work is organised the way you already think about it: areas of
  your life or business, the initiatives in each, the epics that deliver them, and the tasks that
  make up an epic. Each persona (a Claude account) sees its own areas, and only those.
- **Plan in Claude.** Open your roadmap in Claude and talk it through. Claude reads the real
  tasks and dependencies, proposes changes, and makes the ones you accept.
- **Build in the terminal.** Every new terminal tab opens on your areas with their ready work.
  Pick a task, or choose "something new" and Claude helps you shape the idea into a task before
  writing a line of code.
- **Sessions that keep their place.** Each session knows its task and gets its goal back when
  Claude's memory of the conversation fills up and is summarised. Restart your computer and every session comes back. One view shows which
  sessions are waiting on you.
- **Shipping, not just coding.** Work happens on its own branch with your private setup applied,
  moves through review and CI, and is only cleaned up once it is safely merged.
- **Always current.** When a new version is out, the launcher says so and tells you what
  changed; one command updates.
- **A weekly rhythm.** An unattended review each weekend checks every backlog against your
  goals and proposes changes for you to accept; a monthly strategy session updates the goals.

Workbench is free and open source (MIT). It runs on your own machine with your own Claude
account; your plans and tasks stay with you. Once Claude Code is installed, getting started takes about ten minutes: a guided setup
installs beads, asks about your projects, sets each one up, connects Claude, and opens your
first roadmap.

"I had eleven terminal tabs and three half-finished ideas every Monday," said Sam Rivera
(an illustrative user, not a real person), a designer who builds tools for clients and for
herself. "Now I sort out the week with Claude on Monday morning, and when I open a terminal the
work is just there, in order."

---

## FAQ

### For people thinking of using it

**Who is it for?**
Anyone building with AI across more than one or two streams of work: product managers,
designers, founders, and developers. You don't need to be a developer. Planning happens in Claude; the terminal part is picking
from a list and pressing Enter, and Claude Code does the rest. You do need to be comfortable
opening a terminal.

**Do I have to follow a process?**
No. Workbench suggests: it offers to shape an idea before building, it offers to close out
finished work, it flags a backlog that has drifted from your goals. You can skip any of it.
It insists on one thing only: it won't delete work that isn't safely saved.

**What does it cost?**
Workbench is free. It runs Claude on your own account, so Claude usage counts against your own
plan, the same as using Claude yourself. The one thing that uses Claude on a schedule is the
weekly review, and only for areas where you've set goals; you can turn it off.

**Where does my data live?**
On your machine, in each project's own task store (beads). Workbench sends nothing anywhere
except to Claude, the same way any Claude session does, a once-a-day check with GitHub for a
newer version, which you can turn off, and, when you close out a branch that isn't in your main
branch's history, a question to GitHub through your own `gh` about whether a pull request merged it. Beads itself sends anonymous usage metrics (which
commands run, never your tasks); `bd metrics off` stops them, and setup says so. Workbench has
no server and no account. The one exception is the optional roadmap page you can open anywhere: it is a page in your own Claude
account, so it holds a copy of the tasks it shows, readable only by you unless you make someone an editor.

**What do I need?**
A Mac, Claude Code, and beads (the task tracker workbench is built on). Planning in Claude works
in the Claude Desktop app, and the roadmap page opens anywhere you use Claude. Changes made on the
page wait there until you sync from your Mac.

**Why not just a to-do list?**
For one or two streams, a to-do list is enough, and workbench would be overhead. It earns its
place when you're running several streams and the hard part is remembering what's in flight
across all of them.

**Why not Claude Projects, or Claude Code on its own?**
A Claude Project is a folder of context for a conversation. Claude Code's unit is a session.
Neither holds a roadmap with dependencies across all your areas, and neither connects the
thinking to the building. Workbench uses both for what they're best at and adds the layer between.

**Why not Linear, Notion or GitHub Projects connected to Claude?**
If your team already plans there, keep doing so. Workbench is for one person across many areas,
with tasks that live next to the code, cost nothing and need no account, and with the terminal
opening on them.

### What works today

As of November 2026, the build side is real and in daily use, planning in the Claude Desktop
app works, a roadmap page shows your tasks on the web and phone, and a guided first run sets it all up.

- **Works today:** the launcher in every new terminal tab (Apple Terminal), showing your spaces
  with ready-task counts, then the space's tasks with what's next and what needs attention;
  "something new", where Claude shapes an idea into a task before building, offering a light spec
  with done-when checks that you can skip; a Claude account and
  colour per space; a worktree per task with private setup and teardown hooks, and a close-out
  that refuses to lose work and runs itself when you leave a session; status lines showing the session's task and space; `wb-tabs`
  (which sessions are waiting on you); session restore after a restart; `wb-tidy` (end the
  finished worktrees); weekly unattended grooming with a review, and a monthly strategy session;
  a "time to restart" hint; a guided first run (`wb-setup`: tools, your projects, the config,
  `bd init`, a demo space, the `~/.zshrc` line, connecting the Claude Desktop app) and a health
  check (`wb-doctor`); planning in the Claude Desktop app against your real tasks
  (`wb-mcp connect`), seeing only the signed-in account's spaces and keeping workbench's rules;
  numbered releases with a changelog, a notice on the launcher's first screen when a new version
  is out (a once-a-day check you can turn off), and `wb-update` to bring you current in one step;
  a way to tell us how it's going without telemetry: GitHub issue forms for bugs and ideas, and
  an opt-in "tell us your setup" form; shipping after the commit (`wb-ship`: push, pull request,
  CI, and the merge on your yes), with close-out recognising squash merges; a roadmap page in
  your own Claude account that opens on the web and the phone, showing each area's open tasks and
  taking changes (title, priority, a note, a new task), which a Claude Code session on your Mac
  applies under the same rules when you sync (`wb-roadmap sync`).
- **Partly there:** areas exist as *spaces* (with an optional group), and epics and tasks exist as
  beads, but there is no initiative layer or roll-up across spaces. Shaping before code exists,
  but there is no light spec or acceptance-criteria step.
- **Not built:** planning by chat on the web or phone (the roadmap page takes changes there, but
  they wait for a sync from the Mac, and there is no continuous sync); review
  on pull requests and releasing what merged; a single "vibe to strict" setting for how much
  workbench suggests.

### For us (internal)

**What's the hardest part?**
The Claude connection. The work is making it feel like one roadmap: workbench has to tell Claude
which areas exist, keep Claude's edits inside the rules workbench uses (labels, epics, protected
work), and do it without a setup step a non-developer would stumble on. Beads ships its own MCP
server (`beads-mcp`), but it takes any folder and can close, reopen and repair anything, so
workbench runs its own small one (`wb-mcp`) that knows the spaces and keeps the rules.

**One roadmap, or one per persona?** *(Decided, November 2026.)*
One per persona. A persona is a Claude account; the Claude Desktop app is signed in to one at a
time, and work and personal shouldn't read each other's tasks. So workbench is persona-agnostic:
connected as a persona, it shows and edits that persona's areas only, and the terminal side
already starts each area on its own account. A view across personas (say, a router in front of
several accounts) is a reasonable thing for someone to build later, but it is not needed now.

**Why start with the Desktop app?**
Because a local server is enough there: the Desktop app runs one on your Mac, so your tasks
never leave it. So the first version is Desktop. The second is a roadmap page you can open anywhere (a published Claude artifact
holding a copy of your tasks). Only a Claude Code session on your Mac can reach the page's data, so it syncs when you ask, not
continuously. Putting your tasks on a hosted server so
the web can reach them is not planned: it breaks "your data stays with you".

**What's not planned?**
Teams and shared backlogs, a hosted service, Windows and Linux (for now), and replacing beads or
Claude Code. Workbench stays a thin layer over both.

**What are the risks?**
Claude Code keeps absorbing session management (agent view, worktrees, cleanup), so anything
workbench does there may become redundant; the lasting part is the task-first policy and the
link to planning. Beads changes quickly, so workbench only ever talks to it through the `bd`
command. And the evidence is uneven across levels: it's strong that people lose track of many
*sessions*, and thinner for the levels above (many projects, many personas). Workbench starts at
sessions for that reason and works upwards; the launch should test the upper levels, not assume
them.

**How will we know it's working?**
Workbench has no telemetry and won't add any, so we ask: interviews with a handful of early
users and the opt-in "tell us your setup" form. We're listening for people still using
it four weeks later, running several areas rather than one, editing the roadmap in Claude each
week, and no longer finding forgotten sessions and worktrees.

---

## Words used here

- **Persona**: one Claude account, such as work or personal. Workbench works the same in each,
  and keeps each persona's work to itself.
- **Area** (in today's config, a *space*): a part of your life or business with its own projects,
  such as work, a side business or family.
- **Task** (a *bead*): one piece of work, tracked by [beads](https://github.com/gastownhall/beads).
  An **epic** is a task made of smaller tasks; an **initiative** groups epics toward one goal.
- **Worktree**: a private copy of a project's folder for one task, so two tasks never trip over
  each other's half-finished changes.
- **Grooming**: the weekly review of a backlog against your goals.

## Gaps between this vision and today

Each promise in the press release, what exists, and what closes the gap. All of them sit under the
epic wb-kvx, with the launch post (wb-kvx.13). Gaps 1, 2, 4, 6, 7, 12 and 13 closed in November 2026
and moved to "What works today": plan in Claude (wb-kvx.1, for the Desktop app), the roadmap page
on the web and phone, synced when you ask (wb-kvx.2), guided setup
(wb-kvx.4), an optional done-when step when shaping something new (wb-kvx.6), shipping after the
commit with `wb-ship` (wb-kvx.7), issue forms and the "tell us your setup" form (wb-kvx.12) and
update notices with `wb-update` (wb-kvx.14). Review, the part of
the shipping promise gap 7 didn't cover, is gap 14. Timing setup for a person, which gap 4 left open, is
part of the newcomer test of the getting-started guide (wb-kvx.21).

| # | Promise | Today | Gap | Bead |
|---|---|---|---|---|
| 3 | Areas → initiatives → epics → tasks | Spaces (with a group), beads with parent epics | An initiative layer and a roll-up view across spaces | wb-kvx.3 |
| 5 | Usable by non-developers | A README written for developers; a getting-started guide through the plan, groom and build loop (`docs/getting-started.md`), with its own word list and pictures of the launcher's two screens (`scripts/screenshots.sh`) | A picture or short recording of a Claude session at work, and the guide tried by someone new to workbench | wb-kvx.26, wb-kvx.21 |
| 8 | Suggests rather than insists | Mostly suggests; strict only where work could be lost | One setting from "vibe" to "strict" that every prompt respects | wb-kvx.8 |
| 9 | Sessions that keep their place | Restore, `wb-tabs`, `wb-tidy`, status lines, compaction recovery | A morning summary of what's in flight across everything | wb-kvx.9 |
| 10 | A weekly rhythm | Weekly grooming, review, monthly strategy | Retro: what shipped this week against the goals | wb-kvx.10 |
| 11 | Anyone can try it | macOS and Apple Terminal only | Other terminals first; other systems not planned yet | wb-kvx.11 |
| 14 | Shipping moves through review | `wb-ship` opens the pull request, waits for CI and merges on your yes; review is left to you | AI review on every pull request, low-risk changes merged on green, a short brief on risky ones | wb-kvx.18 |

## Keeping this true

This file is meant to be the source of the workbench space's own goals. Once it is agreed, the
space's `goals.md` (the private plan weekly grooming reads) names the promises above, so each
Saturday the grooming run flags beads that serve no promise and promises with no beads. When a gap closes, its row moves into
[What works today](#what-works-today) in the same commit. The launch post is cut from the press
release; promises 1 and 4, which it waited for, now work.
