#!/usr/bin/env bash
# The feedback channel (vision gap 12): GitHub issue forms. GitHub only renders them from the
# default branch and says nothing about a broken one, so these checks stand in. No YAML parser:
# CI's python has no PyYAML, and these files are simple enough to read line by line.
source "$(dirname "$0")/lib.sh"
D="$REPO/.github/ISSUE_TEMPLATE"

for f in bug.yml idea.yml setup.yml config.yml; do
  if [ -f "$D/$f" ]; then ok "$f exists"; else bad "$f exists"; fi
done

for f in bug.yml idea.yml setup.yml; do
  [ -f "$D/$f" ] || continue
  body=$(cat "$D/$f")
  for key in name: description: body:; do
    if grep -q "^$key" "$D/$f"; then ok "$f has top-level $key"; else bad "$f has top-level $key"; fi
  done
  # A repeated id breaks the form, and GitHub only shows that when someone opens it.
  dups=$(sed -n 's/^ *id: *//p' "$D/$f" | sort | uniq -d)
  assert_eq "$f: no id repeats" "$dups" ""
  # The repo is public, and so is every issue: the form says so before anything is typed.
  assert_contains "$f warns that issues are public" "$body" "public"
  assert_contains "$f asks for no private names" "$body" "names"
done

# Opt-in means every answer is optional: one required field and it is no longer a choice.
setup=$(cat "$D/setup.yml" 2>/dev/null)
assert_not_contains "setup form: no field is required" "$setup" "required: true"
# It asks after the vision's four signs that workbench is working (docs/vision.md).
assert_contains "setup form: how long you've used it" "$setup" "How long"
assert_contains "setup form: how many areas" "$setup" "How many"
assert_contains "setup form: editing the roadmap in Claude" "$setup" "roadmap"
assert_contains "setup form: forgotten sessions and worktrees" "$setup" "forgotten"
assert_contains "setup form: interviews are opt-in" "$setup" "interview"
assert_not_contains "setup form: no email field (the GitHub handle is the contact)" "$setup" "email"

# Every link to a form names a template that exists.
links=$(grep -ho 'issues/new?template=[A-Za-z0-9_.-]*' "$REPO/README.md" "$REPO/docs/getting-started.md" | sort -u)
assert_contains "the README links the setup form" "$links" "template=setup.yml"
for l in $links; do
  t=${l#*template=}
  if [ -f "$D/$t" ]; then ok "link to $t resolves"; else bad "link to $t resolves"; fi
done

# Gap 12 closed: its row leaves the gap table.
gaps=$(sed -n '/^## Gaps between/,/^## Keeping/p' "$REPO/docs/vision.md")
assert_not_contains "vision: gap 12 no longer in the gap table" "$gaps" "| 12 |"

finish
