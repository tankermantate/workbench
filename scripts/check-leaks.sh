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
# as a term it would match nearly every file and commit.
self="$(basename "$(git -C "$repo" rev-parse --show-toplevel)")"
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
if [ "$found" -eq 1 ]; then
  echo "check-leaks: the lines above name something from your private config. Fix them (history needs a rewrite) before pushing." >&2
  exit 1
fi
echo "check-leaks: clean ($(wc -l < "$terms" | tr -d ' ') terms checked, files + history + commit messages)"
