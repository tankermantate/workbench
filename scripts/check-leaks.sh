#!/usr/bin/env bash
# Run before any push. Fails if a tracked file, any commit in history, or a
# commit message names a space, profile, user or email from this machine's
# private config. Whole words, any case. History counts because a push
# publishes every commit, not just the current files.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="${WB_LEAK_REPO:-$here}"
terms="$(mktemp)"; trap 'rm -f "$terms"' EXIT
# The repo's own name is public, even when a space is named after the repo;
# as a term it would match nearly every file and commit. The name comes from the
# main checkout (the folder holding the shared .git), not this one: a sibling
# worktree like workbench-groom is still the workbench repo.
main="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)"
if [ "$(basename "$main")" = .git ]; then main="$(dirname "$main")"; fi
self="$(basename "$main" .git)"
{ "$here/bin/wb-spaces" --leak-terms; id -un; git -C "$repo" config user.email || true; } \
  | awk 'length($0) >= 3' | { grep -v -i -x -F -- "$self" || true; } | sort -u > "$terms"
found=0
git -C "$repo" grep -n -I -w -i -F -f "$terms" -- . && found=1
revs="$(git -C "$repo" rev-list --all 2>/dev/null || true)"
if [ -n "$revs" ]; then
  # shellcheck disable=SC2086
  git -C "$repo" grep -l -I -w -i -F -f "$terms" $revs -- . | sed 's/^/history: /' && found=1
  if git -C "$repo" log --all --format='%h %B' | grep -n -w -i -F -f "$terms" | sed 's/^/commit message: /' | grep . ; then
    found=1
  fi
fi
# The bead store syncs to the remote too. With no remote nothing carries it yet,
# so a finding only warns; once a remote is set, it (or a store we can't scan) fails.
# The store is untracked, so only the main checkout has it, whichever worktree runs this.
beads_note=""
if [ "${WB_LEAK_SKIP_BEADS:-}" = 1 ]; then
  beads_note=", bead db skipped (WB_LEAK_SKIP_BEADS=1)"
else
  brc=0; beads="$(python3 "$here/scripts/check-leaks-beads.py" "$terms" "$main")" || brc=$?
  remote="$(printf '%s\n' "$beads" | sed -n 's/^remote: //p')"
  if [ "$brc" -ne 0 ]; then
    printf '%s\n' "$beads" | grep -v '^remote: ' >&2 || true
    if [ -n "$remote" ]; then
      found=1
      echo "check-leaks: a remote is set ($remote), and bd sync would publish the bead db. Scrub those beads and flatten their history (bd flatten), or remove the remote. To skip the bead db: WB_LEAK_SKIP_BEADS=1." >&2
    else
      beads_note=1
    fi
  fi
fi
if [ "$found" -eq 1 ]; then
  echo "check-leaks: the lines above name something from your private config. Fix them (history needs a rewrite) before pushing." >&2
  exit 1
fi
n="$(wc -l < "$terms" | tr -d ' ')"
if [ "$beads_note" = 1 ]; then
  echo "check-leaks: files + history + commit messages clean ($n terms checked), but the bead db is NOT (lines above). No remote is set, so nothing carries it yet: scrub it before adding one."
else
  echo "check-leaks: clean ($n terms checked, files + history + commit messages$beads_note)"
fi
