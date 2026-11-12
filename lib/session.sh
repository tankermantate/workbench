# lib/session.sh — helpers shared by bin/new-session and bin/end-session.
# Source it after setting WB_HOME (this repo's top). bash 3.2.
# Spec: docs/specs/2026-10-18-session-scripts-design.md

# wb-spaces rows, one per line, in config order; returns wb-spaces' exit code.
ws_rows() { "$WB_HOME/bin/wb-spaces"; }

# ws_split ROW: one row into S_*; '-' becomes empty.
ws_split() {
  local f
  IFS=$'\t' read -r S_LABEL S_GROUP S_ROOT S_BEADS S_WORKTREES S_SESSION_CMD S_KEY \
    S_CLAUDE_CONFIG S_PROTOCOL S_SAFE S_GH_ACCOUNT S_ON_CREATE S_BEFORE_END S_AFTER_END <<< "$1"
  for f in S_LABEL S_GROUP S_ROOT S_BEADS S_WORKTREES S_SESSION_CMD S_KEY S_CLAUDE_CONFIG \
           S_PROTOCOL S_SAFE S_GH_ACCOUNT S_ON_CREATE S_BEFORE_END S_AFTER_END; do
    if [ "${!f}" = "-" ]; then printf -v "$f" '%s' ""; fi
  done
}

# ws_find_key ROWS KEY: S_* = the worktree space with that key.
ws_find_key() {
  local r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ws_split "$r"
    if [ "$S_WORKTREES" = 1 ] && [ "$S_KEY" = "$2" ]; then return 0; fi
  done <<< "$1"
  return 1
}

# ws_keys ROWS: the worktree space keys, for error messages.
ws_keys() {
  local r out=""
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ws_split "$r"
    if [ "$S_WORKTREES" = 1 ]; then out="$out${out:+, }$S_KEY"; fi
  done <<< "$1"
  printf '%s' "${out:-none}"
}

# ws_timeout SECS CMD…: CMD in its own process group, killed whole (children too,
# which would otherwise hold our output pipe open) after SECS: exit 124. Ctrl-C
# reaches only this wrapper, since CMD's group isn't the terminal's, so INT and
# TERM take CMD's group down too. A CMD killed by a signal exits 128+signal.
ws_timeout() {
  perl -e '$t = shift; $p = fork; if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 }
           $SIG{ALRM} = sub { kill "KILL", -$p; exit 124 };
           $SIG{INT} = $SIG{TERM} = sub { kill "KILL", -$p; exit 130 };
           alarm $t; waitpid($p, 0);
           exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$@"
}

# ws_quote ARG…: the args as one shell-quoted line, for commands we print.
ws_quote() {
  local a out=""
  for a in "$@"; do out="$out${out:+ }$(printf '%q' "$a")"; done
  printf '%s' "$out"
}

# ws_bead_info ROOT ID: BEAD_TYPE and BEAD_TITLE from 'bd show ID --json' in ROOT.
# bd can print 'Warning: …' lines before the JSON; a slow bd counts as not found.
ws_bead_info() {
  local out
  out=$(cd "$1" && ws_timeout "${WB_BD_TIMEOUT:-5}" "${WB_BD:-bd}" show "$2" --json 2>/dev/null </dev/null) \
    || return 1
  # The JSON is the first line-start '[' or '{' that parses: noise like
  # '[warn] …' can look like JSON too.
  out=$(printf '%s' "$out" | python3 -c '
import json, re, sys
t = sys.stdin.read()
for m in re.finditer(r"^[\[{]", t, re.M):
    try:
        b = json.JSONDecoder().raw_decode(t[m.start():])[0]
    except ValueError:
        continue
    if isinstance(b, list):
        b = b[0] if b else None
    if isinstance(b, dict):
        clean = lambda v: " ".join(str(v or "").split())
        print(clean(b.get("issue_type")), clean(b.get("title")), sep="\t")
        sys.exit(0)
sys.exit(1)
' 2>/dev/null) || return 1
  BEAD_TYPE=${out%%$'\t'*}
  BEAD_TITLE=${out#*$'\t'}
  [ -n "$BEAD_TITLE" ]
}

# ws_has_store ROOT: ROOT has a bead store of its own — a .beads between it and
# its repo's top. bd itself walks further up, into stores that aren't this space's.
ws_has_store() {
  local root top
  root=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || return 1
  top=$(cd "$top" && pwd -P)
  [ -n "$(ws_store_dir "$root" "$top")" ]
}

# ws_find_bead ROWS ID: S_* and BEAD_* for the first worktree space whose own store has ID.
ws_find_bead() {
  local r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ws_split "$r"
    if [ "$S_WORKTREES" = 1 ] && [ "$S_BEADS" != false ] && ws_has_store "$S_ROOT" \
       && ws_bead_info "$S_ROOT" "$2"; then
      return 0
    fi
  done <<< "$1"
  return 1
}

# ws_default_branch REPO: origin/HEAD's target, else main, else master, else the
# current branch. Both scripts use it, so they agree on what "merged" means.
ws_default_branch() {
  local b
  if b=$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "${b#origin/}"; return 0
  fi
  for b in main master; do
    if git -C "$1" show-ref --verify --quiet "refs/heads/$b"; then printf '%s\n' "$b"; return 0; fi
  done
  git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'main\n'
}

# ws_store_dir DIR TOP: the nearest bead store from DIR up to TOP (both resolved),
# or nothing. A store is a .beads with bd's config.yaml or metadata.json; a .beads
# without them (exports, logs left behind) is skipped, as bd itself skips it.
ws_store_dir() {
  local d=$1
  while :; do
    if [ -f "$d/.beads/config.yaml" ] || [ -f "$d/.beads/metadata.json" ]; then
      printf '%s\n' "$d/.beads"; return 0
    fi
    if [ "$d" = "$2" ] || [ "$d" = / ]; then return 0; fi
    d=$(dirname "$d")
  done
}

# ws_relpath PATH BASE: PATH relative to BASE.
ws_relpath() { perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0], $ARGV[1]), "\n"' "$1" "$2"; }

# ws_slugify WORDS…: lowercase, non-alphanumerics to '-', dashes collapsed, 40 chars.
ws_slugify() {
  local s
  s=$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]' \
      | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' | cut -c1-40 | sed 's/-$//')
  if [ -z "$s" ]; then echo "'$*' has no letters or digits to name a branch with" >&2; return 1; fi
  printf '%s\n' "$s"
}

# ws_gh_switch ACCOUNT: make ACCOUNT gh's active account. Only ever warns: the
# fetch is tried either way, and it may already work.
ws_gh_switch() {
  local gh=${WB_GH:-gh} active
  if ! command -v "$gh" >/dev/null 2>&1; then
    echo "  warning: gh not found; can't switch GitHub to $1, so the fetch may fail." >&2
    return 0
  fi
  active=$("$gh" auth status --active 2>/dev/null | sed -n 's/.*account \([^ ]*\) .*/\1/p' | head -n 1) || true
  [ "$active" != "$1" ] || return 0
  if "$gh" auth switch --user "$1" >/dev/null 2>&1; then
    echo "→ gh: switched to $1"
  else
    echo "  warning: couldn't switch gh to $1, so the fetch may fail (try: gh auth login --user $1)." >&2
  fi
  return 0
}

# ws_run_hook CMD DIR: a space's hook, in DIR, with the WB_* variables the caller exported.
ws_run_hook() { (cd "$2" && sh -c "$1"); }
