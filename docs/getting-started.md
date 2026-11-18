# Getting started with workbench

This guide takes you from nothing installed to your first full loop: you plan your roadmap in a
Claude chat, workbench grooms the backlog, and a Claude Code session builds the top task. It
takes about an hour the first time, most of it spent talking to Claude. The [README](../README.md)
is the reference; this page is the story, and it links there for the details.

**What workbench is for, in one sentence:** it keeps your roadmap in order across all your
projects, so whenever you open a terminal you know what matters most and Claude starts on it.

## The loop

```
  plan in a chat           groom the backlog           build in the terminal
  (Claude Desktop app)  →  (weekly, or on demand)   →  (a Claude Code session per task)
  file, split, sharpen     put the right tasks in      pick the top task; Claude
  and prioritise tasks     NOW, check them against     starts on it and closes it
                           your goals                  when it's done
          ↑                                                         │
          └─────────────── the same tasks, nothing copied ──────────┘
```

All three steps read and write the same tasks, kept in each project's own task store
([beads](https://github.com/gastownhall/beads)). A task you file in the chat is in the launcher
the next time you open it, and a task a session closes disappears from the chat's roadmap.

A few words you'll meet (the [vision's glossary](vision.md#words-used-here) has more):

- **Space**: a project folder (or a folder of projects) the launcher offers. Think of it as an
  area of your work.
- **Bead**: one task in a space's backlog. An **epic** is a bead made of smaller beads. Each
  has a priority from 0 (most urgent) to 4 (someday).
- **Backlog**: a space's open beads. **NOW** and **NEXT** are the sprint that grooming picks
  (the labels `wave:1` and `wave:2`); **icebox** is for beads parked on purpose.
- **Plan**: a space's goals, what's protected, and what's due, in
  `~/.config/workbench/plans/<space>/`. Grooming judges the backlog against it.

## 1. Install, and open the launcher

You need a Mac, zsh (the macOS default) and Apple Terminal. Install
[Claude Code](https://docs.claude.com/en/docs/claude-code), then run `claude` once in Terminal
and log in. Then:

```bash
git clone https://github.com/tankermantate/workbench.git ~/dev/workbench
~/dev/workbench/bin/wb-setup
```

`wb-setup` asks before each change. Press Enter to take the default in brackets.

1. It checks your tools and offers to install the missing ones with Homebrew, including beads.
2. It links workbench's commands into `~/.local/bin` and offers to schedule the background jobs.
   Say yes if you want weekly grooming; you can add it later by re-running `install.sh`.
3. It asks for your project folders. Add one real project if you like, and **say yes to the
   Demo space**: this guide uses it.
4. It adds the launcher line to `~/.zshrc`.
5. It offers to connect the Claude Desktop app. Say yes if you have Desktop (step 2 below
   covers it).

It ends with `wb-doctor`, one line per check. `!!` lines say what to fix; run `wb-doctor` again
any time.

**Check:** open a new Terminal window. The launcher shows your spaces with their bead counts.
Pick **Demo**: you see three sample tasks. Press esc for a plain shell, and type `launch` to
bring the launcher back.

More: [Set up](../README.md#set-up) in the README.

## 2. Connect the Claude Desktop app

Planning happens in a chat, against your real beads. Today that chat is the
**Claude Desktop app** on the same Mac. claude.ai on the web and on your phone can't reach your
beads yet: that's the roadmap view, still to be built (wb-kvx.2).

If `wb-setup` connected Desktop, skip to the check. Otherwise:

1. Install the [Claude Desktop app](https://claude.ai/download) and sign in.
2. Quit Desktop (Claude › Quit Claude). `wb-mcp connect` won't run while Desktop is open,
   because Desktop writes its settings back over any change.
3. In Terminal, run `wb-mcp connect`. Then open Desktop again.

**Check:** run `wb-mcp check`. It says whether workbench is connected and lists the spaces
Desktop can see. Desktop sees only the spaces of the account it's signed in as. A space belongs
to the account Claude Code uses for it: your default `claude` login, unless the space sets
`claude_config`. If Demo is missing from the list, sign Desktop in to the account you logged
`claude` in to.

**Triage something from chat.** In a new Desktop chat, try:

> Using workbench, show me the Demo space's backlog. Then file a new task in Demo: "Write a
> one-page note on what this project is for", priority 1, with a line saying what done looks
> like. Then raise "See every session at once: wb-tabs" to priority 2.

Claude lists the beads, files the new one and changes the priority, and tells you what it did.
Open a new Terminal tab and pick Demo: the new task is there.

What Claude can do from the chat: list and read beads, file new ones (under an epic, too),
sharpen titles, descriptions and done-when lines, change priority and labels, and say that one
bead waits on another. What it can't do: close, claim or defer a bead (the session that does the
work closes it), or touch grooming's labels (NOW, NEXT, icebox, attention). It also can't lower
the priority of a protected bead, and until a space has a plan (step 4) every bead counts as
protected, so in Demo you can raise a priority but not lower one. Planning stays planning, and the sprint stays grooming's call
and yours.

More: [Plan in Claude Desktop](../README.md#plan-in-claude-desktop) in the README.

## 3. What workbench is for

With a few projects on the go, the hard part is staying oriented: knowing what's in flight,
where it is, and what should come next. Workbench splits that into three steps and gives each
one to the tool that does it best:

- **Thinking and planning happen in a chat**, where Claude is a good thinking partner. You talk
  the roadmap through: split an epic into tasks, write what done looks like, decide what matters
  this week. What you agree on is saved as beads straight away.
- **Grooming keeps the backlog honest.** Once a week, or whenever you ask, a read-only Claude
  reads every open bead against the space's plan. It puts the right few beads in NOW and NEXT,
  flags what needs attention, and proposes the rest for you to accept or reverse.
- **Building happens in the terminal**, where Claude Code is a good builder. Every new tab opens
  on your spaces. You pick the top bead, and Claude starts in that project's folder already
  knowing which bead it's on and what done looks like. When the work is done, the session closes
  the bead.

You are the product owner. Claude in the chat helps you decide, grooming keeps the order
current, and each Claude Code session is a member of your team, building one bead at a time.

## 4. Groom the backlog, then build the top bead

Grooming judges a backlog against a **plan**: your goals for the month, what's protected, what's
due. A space without a plan can still be groomed, but nothing is applied until it has one, and
its summary leads with "strategy session needed". So the first time through goes like this:

**a. A first grooming run.** In Terminal:

```bash
wb-groom run Demo
```

This runs Claude once (it counts against your Claude usage, like any session) and takes a few
minutes. It reads the backlog, guesses at the space's goals and writes a summary, but applies
nothing yet, because Demo has no plan. Use the space's name as the launcher shows it.

**b. The strategy session.** Open a new Terminal tab and look at Demo on the first screen: it
now ends with `groomed <day> · review · strategy due`. Pick Demo, then **✦ strategy session**.
Claude drafts the plan from what grooming guessed, then goes through it with you one file at a
time: 3–5 goals in your words, what's protected, anything dated. The last step sets the plan's
date, and from then on grooming counts the plan as real. For Demo, goals like "learn the
launcher" and "try planning in Desktop" are enough. Type `/exit` when Claude says it's done.

**c. Groom again, and review it.**

```bash
wb-groom run Demo
```

This time grooming applies what it's allowed to on its own: it puts beads in NOW and NEXT,
iceboxes unprotected beads that serve no goal, and flags beads that need attention. Everything
else becomes a proposal for you to decide. Open a new tab: Demo shows `groomed <day> · review`.
Pick Demo, then **✦ review <day>'s grooming**. Claude walks you through the summary one group at
a time (what's due, the new sprint, the proposals) and applies what you accept. To put back
something grooming applied, tell Claude: it undoes that bead exactly. When you've been through it
all, Claude marks the run reviewed.

The first run, from step a, is still waiting for review too, and it comes
back as `review` once this one is done. It ran before Demo had a plan, so there's nothing in it
to decide: before you finish, ask Claude to mark it reviewed as well
("mark the earlier grooming run reviewed too"). Then the `review` note goes away.

From now on, if you said yes to the schedule in `install.sh`, grooming runs on its own every
Saturday at 06:00 for each space with a plan. You only do step c's review. Once a month, or when
the plan is 30 days old, the launcher shows `strategy due` again.

**d. Build the top bead.** Open a new tab and pick Demo. The work screen puts the top of the
backlog first:

- beads that need attention (due soon, or protected and neglected);
- in a longer backlog, "Start here": the top three ready beads and why each was picked;
- then the NOW section, then NEXT, then the rest, highest priority first.

Pick the top bead. Claude starts in the space's folder, claims the bead and is told its
description and what done looks like. In a space with `worktrees = true`, the bead also gets its
own copy of the project (a worktree) so tasks don't trip over each other. Work with Claude until
the bead is done; it closes the bead and tells you to `/exit` and start the next one in a fresh
tab.

That's the whole loop. You plan in the chat, grooming sets the order, and each new tab starts
the next session on the bead that matters most.

**Why grooming makes the next session better:** a session is only as good as the bead it starts
on. After a review, the top bead is the one that serves your goals now, at the right priority,
with what done looks like written down. So when you open a tab, the first thing on the screen is
the right thing to do. Claude starts on it already briefed, and knows when it's finished.

More: [Planning rituals](../README.md#planning-rituals) and [Daily use](../README.md#daily-use)
in the README.

## Where next

- Add your real projects: run `wb-setup` again (it skips what's done), or edit
  `~/.config/workbench/spaces.toml` (`spaces.example.toml` documents every key).
- Start each real space's plan the same way: a first `wb-groom run <space>`, then the
  strategy session.
- Remove the Demo space when you're done with it: delete its `[[space]]` from `spaces.toml` and
  the folder `~/.local/share/workbench/demo`.
- See every open session at once with `wb-tabs`, and tidy up finished worktrees with `wb-tidy`.
- Once you've used it a week or two, [tell us your setup](https://github.com/tankermantate/workbench/issues/new?template=setup.yml): a
  short, opt-in form, and the only way we hear how workbench is used.
