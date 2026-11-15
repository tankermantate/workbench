# Tiny assert helpers for plain-bash tests. Source it; call `finish` last.
PASS=0; FAIL=0
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$REPO/tests/fake:$PATH"
export WB_BD_TIMEOUT=1
export WB_LAUNCH_AGENTS_DIR=/nonexistent/wb-launch-agents   # never the real schedule; tests that want one set their own
export WB_RESTORE_DIR=/nonexistent/wb-restore   # never the real restore queue; tests that want one set their own
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
assert_eq()           { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $3"$'\n'"got:      $2"; fi; }
assert_contains()     { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "missing: $3"$'\n'"in: $2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "unexpected: $3"$'\n'"in: $2"; fi; }
finish() { echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
newtmp() { local t="${TMPDIR:-/tmp}"; mktemp -d "${t%/}/wbtest.XXXXXX"; }   # macOS TMPDIR ends in '/'
# setup_repo DIR [BRANCH]: a repo on BRANCH (default main) with one commit,
# pushed to a bare DIR.origin.git that is its origin.
setup_repo() {
  local h=$1 b=${2:-main}
  git init -q --bare -b "$b" "$h.origin.git"
  git init -q -b "$b" "$h"
  git -C "$h" config user.email t@example.com
  git -C "$h" config user.name t
  git -C "$h" remote add origin "$h.origin.git"
  : > "$h/README.md"; git -C "$h" add README.md; git -C "$h" commit -q -m init
  git -C "$h" push -q -u origin "$b"
}
# mkstore DIR…: a bead store bd would use (it has bd's config.yaml) in each DIR.
mkstore() { local d; for d in "$@"; do mkdir -p "$d/.beads"; : > "$d/.beads/config.yaml"; done; }

# the launcher's waiting count runs wb-tabs: no suite reads the real tabs (a suite can override it)
export WB_PS="$REPO/tests/fake/fake-ps"
export WB_OSASCRIPT="$REPO/tests/fake/fake-osascript"   # never the real tab bar
