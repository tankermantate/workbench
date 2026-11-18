# Plan in Claude: the Desktop connection (wb-mcp)

Vision gap 1 (`docs/vision.md`): plan against your real tasks in a Claude chat, not only from the
terminal. The first version is the Claude Desktop app.

## What was checked first (2026-11-17)

- `beads-mcp` 1.3.4 works with bd 1.1.0 and routes each call by `workspace_root`. But it takes any
  path and exposes close, reopen and admin repair, with no allowlist or rule hook, so it can't keep
  Claude inside workbench's rules or inside one persona. **Workbench doesn't use it.**
- Claude Desktop keeps one MCP config per Mac user (`claude_desktop_config.json` in
  `~/Library/Application Support/Claude/`), not one per signed-in account. Its `config.json` records
  the account it is signed in as (`lastKnownAccountUuid`).
- Claude Code records the account a config is signed in to in `<CLAUDE_CONFIG_DIR>/.claude.json`
  (`oauthAccount.accountUuid`), or `~/.claude.json` without one. That is how a space's
  `claude_config` names its persona.
- bd resolves a parent from another store as "not found", but `bd dep add` accepts any id, including
  one from another store. So workbench checks every id itself.

## Design

`bin/wb-mcp`, stdlib python, one file:

- `wb-mcp serve`: an MCP server on stdio (newline-delimited JSON-RPC). It answers `initialize`
  (echoing the client's protocol version, offering tools), `ping`, `tools/list` and `tools/call`;
  it sends no reply to notifications and returns -32601 for other methods. A refusal is a tool result
  with `isError`, so Claude can read why.
- `wb-mcp connect`: adds a `workbench` entry to Desktop's `mcpServers`, keeping everything else in
  that file. It keeps a backup (`.wb-backup`), writes atomically, refuses while Desktop is running
  (Desktop writes the file back from memory), and does nothing when the entry is already there. The
  entry names an absolute python 3.11+ and puts bd's folder on `PATH`, because Desktop starts servers
  with a bare `PATH`, where `python3` is macOS's 3.9 and bd isn't found. `WORKBENCH_CONFIG` and
  `WB_PLANS_DIR` are carried over when set.
- `wb-mcp check`: whether it's connected, the persona, and which spaces it would see.
- `wb-mcp disconnect`: removes the entry.

### One persona

On every tool call (Desktop can switch account while running), the server reads Desktop's account
and keeps the spaces whose `claude_config` account matches and that have a bead store (`beads` not
`false`, and a `.beads` folder). If Desktop's account can't be read, or no space matches, every tool
refuses and says how to fix it. A space is named by its label, never by a path.

### Tools

| Tool | Does |
|---|---|
| `list_spaces` | the persona's spaces: plan state, protected labels, and `protected.md` itself, so Claude can apply its judgement part |
| `list_beads` | a space's open beads (`include_closed` for all), or an epic's children (`parent`) |
| `show_bead` | one bead in full |
| `create_bead` | title, description, acceptance, design, type, priority, labels, parent |
| `update_bead` | the same fields, plus appended notes |
| `add_dependency` | one bead waits on another in the same space |

### The rules it keeps

- Nothing closes, claims, defers or reopens a bead, and there's no status field at all. Those happen
  in the terminal, where the session that did the work closes it. A closed bead can't be edited.
- `wave:1`, `wave:2`, `icebox` and `attention` belong to grooming and the review: Claude can't add or
  remove them.
- **Protected work**: a bead is protected if it has a label from the plan's `protected.md`, or if the
  space's plan is missing or stale (grooming's own `plan_state`, so the two can't drift). On a
  protected bead, priority can only go up and protected labels can't come off. The judgement half of
  `protected.md` is up to Claude, which gets the text and is told to apply it.
- Every id (the bead, a parent, a dependency) must be this space's own bead, checked by `bd show` in
  the space's root, with the returned id matching exactly.

## Not in this version

- The other Claude surfaces (claude.ai on the web, mobile). They can't reach a local stdio server,
  and putting tasks on a hosted server breaks "your data stays with you". A published roadmap
  artifact (wb-kvx.2) is the planned next step.
- A view across personas.
- Choosing the persona by hand. It always follows Desktop's sign-in, so a space whose
  `claude_config` was never logged in is invisible until it is.
