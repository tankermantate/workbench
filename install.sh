#!/usr/bin/env bash
# Link bin/* into ~/.local/bin and print the line to add to ~/.zshrc.
# Idempotent. Never edits ~/.zshrc and never replaces a file it didn't create.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="${WB_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$dest"
for src in "$here"/bin/*; do
  link="$dest/$(basename "$src")"
  if [ -L "$link" ] && [ "$(readlink "$link")" != "$src" ] && [[ "$(readlink "$link")" != "$here"/* ]]; then
    echo "skip: $link points somewhere else ($(readlink "$link")); left alone" >&2; continue
  elif [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "skip: $link exists and is not a symlink; left alone" >&2; continue
  fi
  ln -sfn "$src" "$link"
  echo "linked $link -> $src"
done
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
