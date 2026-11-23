#!/bin/bash
# screenshots.sh — remake the launcher pictures in docs/images/ from a made-up setup.
#
# Everything runs in a throwaway HOME with made-up spaces (Demo, Acme, Garden), so no real
# space, path or account can end up in a picture. Each screen is drawn by the real launcher in
# a fixed-size tmux pane, captured with its colours and rendered to SVG by rich.
#
# Needs: tmux, bd, fzf, and a python with rich (WB_SHOTS_PYTHON, default python3).
# Usage: scripts/screenshots.sh [out-dir]   (default docs/images)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$REPO/docs/images}
PY=${WB_SHOTS_PYTHON:-python3}
COLS=110 ROWS=30
SOCK=wbshots-$$

for t in tmux bd fzf; do
  command -v $t >/dev/null || { echo "screenshots: needs $t" >&2; exit 1; }
done
"$PY" -c 'import rich' 2>/dev/null || { echo "screenshots: $PY has no rich (pip install rich; set WB_SHOTS_PYTHON)" >&2; exit 1; }

W=$(mktemp -d "${TMPDIR:-/tmp}/wbshots.XXXXXX")
trap 'tmux -L $SOCK kill-server 2>/dev/null || true; rm -rf "$W"' EXIT
H=$W/home
mkdir -p "$H/.config/workbench" "$H/.local/state/workbench"
# workbench needs python 3.11+: put the one on this PATH ahead of /usr/bin (macOS's is 3.9)
BIN=$(dirname "$(command -v python3)"):$(dirname "$(command -v bd)"):$(dirname "$(command -v fzf)")

# $1 folder, then title|priority|label|description lines on stdin: a beads store with those tasks.
store() {
  local d=$1 title prio label desc
  mkdir -p "$d"
  (cd "$d" && HOME=$H bd init -q -p "$(basename "$d" | tr 'A-Z' 'a-z')" >/dev/null 2>&1)
  while IFS='|' read -r title prio label desc; do
    [ -n "$title" ] || continue
    set -- create --title "$title" -t task -p "$prio" --silent
    [ -n "$desc" ] && set -- "$@" -d "$desc"
    [ -n "$label" ] && set -- "$@" -l "$label"
    (cd "$d" && HOME=$H bd "$@" >/dev/null)
  done
}

store "$H/dev/demo" <<'EOF'
Try the launcher: pick this task|1|wave:1
Shape something new|2|
See every session at once: wb-tabs|3|
EOF
store "$H/dev/acme" <<'EOF'
Checkout page: show delivery dates|1|wave:1|Customers ask when their order will arrive. Show the estimated delivery date for each item on the checkout page. Done when: the date shows for every in-stock item, and the tests cover a weekend order.
Fix rounding in order totals|0|wave:1|Totals are off by a cent on some orders with a discount. Round once, at the end. Done when: the three reported orders add up and a test pins the rule.
Email receipts as PDF|2|wave:2|Business customers need a PDF receipt for their records.
Product search: typo tolerance|2|wave:2
Move image hosting to the new CDN|3|
Dark mode for the admin pages|4|
EOF
store "$H/dev/garden" <<'EOF'
Plan the spring planting|1|wave:1
Order seeds before March|2|
EOF

cat > "$H/.config/workbench/spaces.toml" <<EOF
[launcher]
update_check = false

[[space]]
name = "Demo"
root = "~/dev/demo"
beads = true
worktrees = false

[[space]]
name = "Acme"
root = "~/dev/acme"
beads = true
worktrees = false
color = "purple"

[[space]]
name = "Garden"
root = "~/dev/garden"
beads = true
worktrees = false
color = "green"
EOF

tmux -L $SOCK -f /dev/null new-session -d -x $COLS -y $ROWS \
  "env -i HOME=$H PATH=$BIN:/usr/bin:/bin TERM=xterm-256color LANG=en_US.UTF-8 PS1='%~ %# ' zsh -f"
tmux -L $SOCK set -g status off

# Waits (up to 20s) until the pane shows $1.
wait_for() {
  local i
  for i in $(seq 1 100); do
    tmux -L $SOCK capture-pane -p | grep -qF -- "$1" && return 0
    sleep 0.2
  done
  echo "screenshots: never saw '$1'; the pane:" >&2
  tmux -L $SOCK capture-pane -p >&2
  exit 1
}

# Waits (up to 20s) until the pane no longer shows $1.
wait_gone() {
  local i
  for i in $(seq 1 100); do
    tmux -L $SOCK capture-pane -p | grep -qF -- "$1" || return 0
    sleep 0.2
  done
  echo "screenshots: '$1' never went away" >&2
  exit 1
}

# $1 file name, $2 title. Captures the pane with its colours and renders it to SVG.
shot() {
  sleep 0.5   # let fzf finish drawing (counts fill in the background)
  tmux -L $SOCK capture-pane -p -e > "$W/$1.ansi"
  "$PY" - "$W/$1.ansi" "$OUT/$1.svg" "$2" $COLS <<'PY'
import sys
from rich.console import Console
from rich.text import Text
src, dst, title, cols = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
lines = open(src, encoding="utf-8").read().rstrip("\n").split("\n")
while lines and not Text.from_ansi(lines[-1]).plain.strip():
    lines.pop()
c = Console(record=True, width=cols, file=open("/dev/null", "w"), color_system="256", force_terminal=True)
for l in lines:
    c.print(Text.from_ansi(l), no_wrap=True, overflow="crop")
c.save_svg(dst, title=title)
PY
  echo "wrote $OUT/$1.svg"
}

mkdir -p "$OUT"
tmux -L $SOCK send-keys "source $REPO/shell/workbench.zsh && launch" Enter
wait_for "Space? ›"
wait_gone "…"   # the counts fill in the background, each one reloading the list
shot launcher-spaces "Workbench: choose a space"

tmux -L $SOCK send-keys "Acme"
wait_for "1/5"
tmux -L $SOCK send-keys Enter
wait_for "Acme ›"
wait_for "NOW"
tmux -L $SOCK send-keys Down Down   # onto the top bead, so the preview shows it
wait_for "Done when"
shot launcher-work "Workbench: choose the work"

tmux -L $SOCK send-keys Escape
