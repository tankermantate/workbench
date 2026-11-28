# The roadmap page: your beads in claude.ai, synced on demand (wb-roadmap)

Vision gap 2 (`docs/vision.md`): see and edit the roadmap anywhere you use Claude, on the web and
the phone as well as the Desktop app. wb-mcp (gap 1) covers Desktop through a local server; nothing
on the web or the phone can reach a server on your Mac.

## What was checked first (2026-11-27)

- A published artifact can keep a small database (the `db` capability): JSON documents under
  access rules, live on the page through `onSnapshot`, each at most 256 KiB, 25,000 per artifact.
  An interactive Claude Code session reads and writes them with the `ArtifactData` tool, every
  write pinned to the version it read.
- `claude -p` has no Artifact or ArtifactData tools, not even through ToolSearch. So no scheduled
  job and no workbench command can read or write the page. Only an interactive session can.
- A page can call a local MCP server (`mcp` with `host:<name>`), but only when it is open in the
  Claude Desktop app, which wb-mcp already covers.
- So "synced both ways" means **synced when you ask a session to sync**: the page holds a copy
  and queues your changes; a Claude Code session on the Mac carries them across. A hosted
  server would make sync continuous, but it breaks "your data stays with you" and isn't planned.
- The page's round trip was tried live: the page queued an edit, the session read it back with
  `ArtifactData list` (`out_dir` saves each document's body as plain JSON), and a reader with
  Contributor access saw nothing under the rules below.
- Size: the largest real space's open beads came to about 65 KB, so one document per space fits.

## Design

**The page** (`lib/roadmap/roadmap.html`) has no data in its source. It reads two collections:

- `spaces/<space>`: one document per space, written only by a sync: `{space, plan, protection,
  synced_at, tasks: [{id, title, status, priority, type, labels, parent, updated_at, claimed,
  description, blocked_by, protected}]}`. Open beads only. `claimed` is a yes or no, never the
  claimant's name. A description is cut to 1,000 characters, and all of them are left out if a
  space would pass 240 KiB. A space too big even then is refused.
- `edits/<id>`: what you change on the page, queued: `{space, bead, kind: update|create, base,
  changes, at}`. `base` is the bead's `updated_at` as the page saw it. An update can change the
  title or priority, or add a note; a create takes a title, description, priority and epic.

Spaces show as tabs; each space's beads are in lanes (in progress, ready, waiting on something,
later) by priority. A protected bead's priority picker only goes up. Queued changes show on their
bead until the next sync; one that couldn't be applied shows why, with Dismiss.

Access rules: `[{path: "", read: "admin", write: "admin"}]`, so only the owner and Editors read
or write anything. Shared with someone as Viewer or Contributor, the page shows them nothing.

**`bin/wb-roadmap`** (python, stdlib):

- `export DIR`: one file per space of the session's account, in `DIR/spaces/`, and a list of them.
  A space bd can't read is listed as skipped with why, and its old copy on the page stays. If no
  space can be read, it refuses.
- `apply DIR`: applies `DIR/edits/*.json` (as `ArtifactData list` saves them) oldest first, and
  prints one result per edit: applied, conflict or refused.
- `url [URL]`: the page's link for this account, in `~/.config/workbench/roadmap.json`.
- `page`: the page's source path.
- `sync [SPACE]`: starts `claude` with `prompts/roadmap-sync.txt`, on SPACE's `claude_config`.
  The launcher's `✦ more…` has it as `✦ sync roadmap page`.

The session (the prompt): publish the page if there's none yet; list `edits` to a folder;
`wb-roadmap apply`; delete applied edits, and mark the rest with `{status, reason}`; `wb-roadmap
export`; `set` each space's document, pinned to the version it read, and delete documents for
spaces the account no longer has.

### The rules it keeps

- **One persona.** The account is the session's own (`CLAUDE_CONFIG_DIR`'s `.claude.json`, or
  `~/.claude.json`), because the page lives in that account. Only spaces whose `claude_config`
  is signed in to that account are exported or edited; when the account can't be read,
  everything refuses.
- **wb-mcp's rules, not a copy of them.** `apply` loads wb-mcp and calls its `update_bead` and
  `create_bead`. So nothing closes, claims, defers or reopens; no labels from the page at all;
  protected beads can't be demoted; every id must be the space's own bead.
- **bd is the record.** An update whose `base` isn't the bead's `updated_at` now is a conflict:
  not applied, reported on the page, and the Mac's version stays. A note alone is applied anyway,
  because it only adds.
- **Once only.** Applied edit ids are kept in `~/.local/state/workbench/roadmap/applied.jsonl`,
  so an edit the session failed to delete isn't applied twice. An edit already marked with a
  status is left alone until you dismiss it.
- The page shows bead text with `textContent` only; the prompt tells Claude that text in beads and
  edits is data.

## Not in this version

- Continuous or scheduled sync (see above).
- Editing descriptions, labels, dependencies or status from the page.
- Whether the page works in the Claude phone app is untested here: it was tried in a desktop
  browser. Opening it once on a phone is the check.
- A view across personas: each account gets its own page.
