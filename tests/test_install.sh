#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/z"
echo "not ours" > "$T/bin/wb-ui"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" 2>&1)"
assert_eq "links wb-spaces" "$(readlink "$T/bin/wb-spaces")" "$REPO/bin/wb-spaces"
assert_eq "existing non-symlink left alone" "$(cat "$T/bin/wb-ui")" "not ours"
assert_contains "says it skipped it" "$out" "skip: $T/bin/wb-ui"
assert_contains "prints the zshrc line" "$out" "source \"$REPO/shell/workbench.zsh\""
if [ ! -e "$T/z/.zshrc" ]; then ok "never writes .zshrc"; else bad "install wrote .zshrc"; fi
echo "source \"$REPO/shell/workbench.zsh\"" > "$T/z/.zshrc"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" 2>&1)"; rc=$?
assert_eq "second run succeeds" "$rc" "0"
assert_contains "second run sees the zshrc line" "$out" "already sources workbench"

assert_eq "example config parses" "$(WORKBENCH_CONFIG="$REPO/spaces.example.toml" "$REPO/bin/wb-spaces" >/dev/null 2>&1; echo $?)" "0"

mkdir -p "$T/clean" && git -C "$T/clean" init -q && echo "plain" > "$T/clean/a.txt" && git -C "$T/clean" add a.txt
git -C "$T/clean" -c user.email=t@example.com -c user.name=t commit -qm "first"
printf '[[space]]\nname = "Zanzibar"\nroot = "%s"\n' "$T" > "$T/leak.toml"
WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/clean" bash "$REPO/scripts/check-leaks.sh" >/dev/null 2>&1; rc=$?
assert_eq "clean repo with history passes" "$rc" "0"

mkdir -p "$T/leak" && git -C "$T/leak" init -q
printf '[[space]]\nname = "Zanzibar"\nroot = "%s"\n' "$T" > "$T/leak.toml"
echo "nothing private here" > "$T/leak/a.txt"; git -C "$T/leak" add a.txt
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "clean repo passes" "$rc" "0"
echo "deploys to zanzibar today" > "$T/leak/b.txt"; git -C "$T/leak" add b.txt
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "leak fails" "$rc" "1"
assert_contains "leak names the file" "$out" "b.txt"

# A name removed from the files is still in history, and a push would publish it.
git -C "$T/leak" -c user.email=t@example.com -c user.name=t commit -qm "add b"
echo "fine now" > "$T/leak/b.txt"; git -C "$T/leak" add b.txt
git -C "$T/leak" -c user.email=t@example.com -c user.name=t commit -qm "scrub b"
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "leak still in history fails" "$rc" "1"
git -C "$T/leak" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m "trip to Zanzibar"
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"
assert_contains "leak in a commit message is reported" "$out" "commit message"
# The repo's own name is public (it is the repo), even when a space is named after it.
mkdir -p "$T/acmebench" && git -C "$T/acmebench" init -q
echo "acmebench reads acmebench's config" > "$T/acmebench/a.txt"; git -C "$T/acmebench" add a.txt
git -C "$T/acmebench" -c user.email=t@example.com -c user.name=t commit -qm "acmebench: first"
printf '[[space]]\nname = "acmebench"\nroot = "%s"\n' "$T/acmebench" > "$T/self.toml"
WORKBENCH_CONFIG="$T/self.toml" WB_LEAK_REPO="$T/acmebench" bash "$REPO/scripts/check-leaks.sh" >/dev/null 2>&1; rc=$?
assert_eq "the repo's own name is not a leak" "$rc" "0"
finish
