# Releases and updates (wb-update)

Vision gap 13: users got changes only when they happened to pull and re-run `install.sh`.

## Releases

- `VERSION` holds the version, `X.Y`. `CHANGELOG.md` has a `## X.Y — <date>` section per release,
  newest first, written for users. A test keeps the two in step.
- A release is a `vX.Y` tag on `main`. `main` only moves by merged pull request, so the bump goes
  through a pull request and the owner tags the merge afterwards. An untagged commit on `main`
  is not a release: it reaches users on their next `wb-update` but triggers no notice.

## The notice

`wb-update --notice` prints `workbench X.Y available: wb-update` (yellow with `--color`) when the
cached latest release is newer than `VERSION`, else nothing. The launcher puts it on the first
screen only (`_wb_first_header`; the numbered menu prints it with `wb-health`'s line).

- **Cache:** `~/.cache/workbench/update.json`, `{"checked": <epoch>, "latest": "X.Y" | null}`,
  written atomically (several tabs can start at once). An unreadable cache counts as stale.
- **Once a day:** when the cache is a day old, `--notice` first claims today's look (rewrites
  `checked`), then spawns `wb-update --refresh` detached, with no handle on the launcher's
  `$(...)` pipe, and answers from the old cache. So the screen never waits on the network, and
  the notice appears from the next launch on.
- **The look:** `git ls-remote --tags --refs origin 'v*'` in the checkout, 5-second timeout,
  no terminal or ssh prompts. Any failure keeps the last known answer. The installed version is
  read live, so the notice goes away as soon as the update lands.
- **Off:** `update_check = false` under `[launcher]` in `spaces.toml`, or `WB_UPDATE_CHECK=off`
  (the tests set it for every suite but this one). A config that doesn't parse turns it off too
  (fail closed: we can't tell it's allowed). Off means no look at all, not just no notice.

## wb-update

In the checkout it was installed from (`bin/..` resolved through the link):

1. Refuse, changing nothing, when it isn't a git checkout, is on a detached HEAD, or has local
   changes to tracked files. Each refusal says how to go on.
2. `git pull --ff-only`. If nothing came, say `workbench X.Y is up to date` and stop.
3. Re-run `./install.sh`, with `--no-schedule` unless a workbench launch agent is already installed.
4. Print `workbench old → new` and the changelog sections newer than the old version, or say it
   pulled fixes with no new release.

Seams: `WB_UPDATE_HOME`, `WB_UPDATE_CACHE`, `WB_UPDATE_FOREGROUND=1` (look inline),
`WB_UPDATE_CHECK`, `WB_LAUNCH_AGENTS_DIR`, `WORKBENCH_CONFIG`. Tests: `tests/test_wb_update.sh`.
