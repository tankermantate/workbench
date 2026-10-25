#!/usr/bin/env bash
# Link bin/*'s commands into ~/.local/bin (dropping our links to ones that are gone), install
# the weekly grooming launch agent, and print the line to add to ~/.zshrc. Idempotent. Never
# edits ~/.zshrc and never replaces a file it didn't create (the launch agent is ours:
# re-running rewrites it).
#   --no-schedule   skip the launch agent
# WORKBENCH_DRY_RUN=1 prints the launchctl commands instead of running them;
# WB_LAUNCH_AGENTS_DIR moves ~/Library/LaunchAgents (the tests use both).
set -euo pipefail
schedule=1
for arg in "$@"; do
  case "$arg" in
    --no-schedule) schedule=0 ;;
    *) echo "usage: install.sh [--no-schedule]" >&2; exit 2 ;;
  esac
done
here="$(cd "$(dirname "$0")" && pwd)"
dest="${WB_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$dest"
# A link into our bin/ whose target is no longer a command (bin/__pycache__, linked by an
# earlier install; a command since removed) is ours and stale. Links anywhere else are left alone.
for link in "$dest"/* "$dest"/.[!.]*; do
  [ -L "$link" ] || continue
  target="$(readlink "$link")"
  case "$target" in "$here"/bin/*) ;; *) continue ;; esac
  if [ ! -f "$target" ] || [ ! -x "$target" ]; then
    rm -f "$link"
    echo "removed $link (no longer a command in $here/bin)"
  fi
done
for src in "$here"/bin/*; do
  [ -f "$src" ] && [ -x "$src" ] || continue  # commands only: python leaves bin/__pycache__ behind
  link="$dest/$(basename "$src")"
  if [ -L "$link" ] && [ "$(readlink "$link")" != "$src" ] && [[ "$(readlink "$link")" != "$here"/* ]]; then
    echo "skip: $link points somewhere else ($(readlink "$link")); left alone" >&2; continue
  elif [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "skip: $link exists and is not a symlink; left alone" >&2; continue
  fi
  ln -sfn "$src" "$link"
  echo "linked $link -> $src"
done
# Saturday 06:00, wb-groom run --all (spec: docs/specs/2026-10-23-planning-rituals-design.md).
# subst TEXT NEEDLE REPLACEMENT: every NEEDLE replaced. Not bash's // expansion: bash >= 5.2 reads an &
# in rep as the match (patsub_replacement), so &lt; would come out <lt;.
subst() {
  local s=$1 out=
  while [[ "$s" == *"$2"* ]]; do out="$out${s%%"$2"*}$3"; s=${s#*"$2"}; done
  printf '%s' "$out$s"
}
xml() { subst "$(subst "$(subst "$1" '&' '&amp;')" '<' '&lt;')" '>' '&gt;'; }
install_schedule() {
  local label=workbench.groom agents="${WB_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
  local groom_dir="${WB_GROOM_DIR:-$HOME/.local/state/workbench/groom}"
  local plist="$agents/$label.plist" tpl path
  if [ -z "${WORKBENCH_DRY_RUN:-}" ] && [ "$(uname)" != Darwin ]; then
    echo "note: launchd is macOS only; weekly grooming not scheduled (run: wb-groom run --all)." >&2; return 0
  fi
  mkdir -p "$agents" "$groom_dir"
  # launchd's PATH is bare: give the run what wb-groom shells out to (bd, claude, python3, git),
  # starting with the ones found here, so it gets the python >= 3.11 checked below and not
  # /usr/bin/python3
  local found="" cmd d env=""
  for cmd in python3 bd claude; do
    d="$(command -v "$cmd" 2>/dev/null || true)"; d="${d%/*}"
    if [ -n "$d" ] && [[ ":$found:" != *":$d:"* ]]; then found="$found${found:+:}$d"; fi
  done
  path="${found:+$found:}$dest:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  # where this shell keeps its plans, run records and spaces, so the agent grooms the same ones
  for cmd in WB_PLANS_DIR WB_GROOM_DIR WORKBENCH_CONFIG; do
    if [ -n "${!cmd:-}" ]; then
      env="$env		<key>$cmd</key>
		<string>$(xml "${!cmd}")</string>
"
    fi
  done
  tpl="$(cat "$here/lib/launchd/workbench.groom.plist.in")"
  tpl="$(subst "$tpl" "@ENV@"$'\n' "$env")"
  tpl="$(subst "$tpl" @LABEL@ "$label")"
  tpl="$(subst "$tpl" @WB_GROOM@ "$(xml "$dest/wb-groom")")"
  tpl="$(subst "$tpl" @PATH@ "$(xml "$path")")"
  tpl="$(subst "$tpl" @LOG@ "$(xml "$groom_dir/launchd.log")")"
  printf '%s\n' "$tpl" > "$plist.tmp" && mv "$plist.tmp" "$plist"
  echo "wrote $plist (Saturdays 06:00: wb-groom run --all)"
  local domain="gui/$(id -u)"
  if [ -n "${WORKBENCH_DRY_RUN:-}" ]; then
    echo "DRY-RUN: launchctl bootout $domain/$label"
    echo "DRY-RUN: launchctl bootstrap $domain $plist"
    return 0
  fi
  # bootout first, so a re-run replaces the loaded agent; it fails harmlessly when none is loaded
  launchctl bootout "$domain/$label" 2>/dev/null || true
  launchctl bootstrap "$domain" "$plist" || echo "note: launchctl bootstrap failed; load it with: launchctl bootstrap $domain $plist" >&2
}
if [ "$schedule" = 1 ]; then install_schedule; fi
command -v fzf >/dev/null || echo "note: fzf not found; the launcher will use a numbered menu (brew install fzf)."
command -v bd  >/dev/null || echo "note: bd not found; spaces will show (bd not installed)."
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' || echo "note: python3 >= 3.11 is required."
line="source \"$here/shell/workbench.zsh\""
if grep -qF "$line" "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null; then
  echo "~/.zshrc already sources workbench."
else
  echo
  echo "Add this line to the END of ~/.zshrc:"
  echo "  $line"
fi
