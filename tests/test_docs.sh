#!/usr/bin/env bash
# The newcomer docs (vision gap 5). GitHub shows a broken image as a bare link and nothing else,
# so these checks stand in: every picture the docs show exists, was made by scripts/screenshots.sh
# from its made-up spaces, and the guide's word list covers the words it uses.
source "$(dirname "$0")/lib.sh"
G="$REPO/docs/getting-started.md"

# Every image a doc links (markdown ![..](path)) exists, relative to that doc.
for doc in "$REPO/README.md" "$REPO"/docs/*.md; do
  for img in $(grep -o '!\[[^]]*\]([^)]*)' "$doc" | sed 's/.*](\([^)]*\))/\1/'); do
    case $img in http*) continue ;; esac
    if [ -f "$(dirname "$doc")/$img" ]; then ok "$(basename "$doc"): $img exists"; else bad "$(basename "$doc"): $img exists"; fi
  done
done

guide=$(cat "$G" 2>/dev/null)
assert_contains "the guide shows the space screen" "$guide" "images/launcher-spaces.svg"
assert_contains "the guide shows the work screen" "$guide" "images/launcher-work.svg"
for w in Space Bead Backlog Plan Worktree Grooming; do
  assert_contains "the guide's word list has $w" "$guide" "- **$w**"
done

# The pictures come from the throwaway setup, never a real one: no home folder, no private
# temp path, and the made-up space names are in them.
for f in "$REPO"/docs/images/*.svg; do
  [ -f "$f" ] || continue
  svg=$(cat "$f")
  assert_not_contains "$(basename "$f"): no home folder" "$svg" "/Users/"
  assert_not_contains "$(basename "$f"): no temp path" "$svg" "/private/"
  assert_contains "$(basename "$f"): the made-up Acme space" "$svg" "Acme"
done

finish
