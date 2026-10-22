"""Which bead a Claude session serves: one small file per session, shared by the
session hooks (bin/wb-session-hook), wb-focus and the status line segment
(wb-statusline-bead). Spec: docs/specs/2026-10-21-session-bead-design.md

  $WB_STATE_DIR/sessions/<session_id>.json   (default ~/.cache/workbench)
  {"bead", "title", "root", "since", "done", "named"}

The status line runs after every reply, so it reads this file and nothing
else; the title is cached here when a session is bound so it never needs bd.
"""
import datetime
import json
import os
import re
import shlex
import signal
import subprocess
import time

BD = os.environ.get("WB_BD", "bd")
READ_TIMEOUT = float(os.environ.get("WB_BD_TIMEOUT", "3"))
WRITE_TIMEOUT = float(os.environ.get("WB_BD_WRITE_TIMEOUT", "30"))
SAFE_ID = re.compile(r"[A-Za-z0-9-]{1,64}")
WORKTREE_RE = re.compile(r"worktree at (/[^)\n]+)\)")  # as in wb-backlog
TITLE_MAX = 40


def state_dir():
    return os.environ.get("WB_STATE_DIR") or os.path.expanduser("~/.cache/workbench")


def binding_path(sid):
    # the id comes from hook stdin or the environment; never let it pick the path
    if not isinstance(sid, str) or not SAFE_ID.fullmatch(sid):
        return None
    return os.path.join(state_dir(), "sessions", sid + ".json")


def load(sid):
    p = binding_path(sid)
    if not p:
        return None
    try:
        with open(p) as f:
            b = json.load(f)
    except (OSError, ValueError):
        return None
    return b if isinstance(b, dict) and b.get("bead") else None


def save(sid, binding):
    p = binding_path(sid)
    if not p:
        return
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".part", "w") as f:  # write-then-rename: the status line may be reading it
        json.dump(binding, f, ensure_ascii=False)
    os.replace(p + ".part", p)


def clear(sid):
    p = binding_path(sid)
    if p and os.path.exists(p):
        os.remove(p)


def prune(days=30):
    d = os.path.join(state_dir(), "sessions")
    cutoff = time.time() - days * 86400
    try:
        names = os.listdir(d)
    except OSError:
        return
    for n in names:
        p = os.path.join(d, n)
        try:
            if os.path.getmtime(p) < cutoff:
                os.remove(p)
        except OSError:
            pass


def short(bead_id):
    return str(bead_id).rsplit("-", 1)[-1]


def run_bd(root, args, timeout):
    """(exit code, stdout), or (None, "") when bd is missing or hangs."""
    try:
        p = subprocess.Popen([BD] + args, cwd=root, text=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    except OSError:
        return None, ""
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # the whole group, as wb-backlog does: a child holding the pipe would keep us waiting
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return None, ""
    return p.returncode, out


def show(root, bead_id):
    rc, out = run_bd(root, ["show", bead_id, "--json"], READ_TIMEOUT)
    if rc != 0:
        return None
    start = re.search(r"^[\[{]", out, re.M)  # bd can print 'Warning: …' lines first
    if not start:
        return None
    try:
        data = json.loads(out[start.start():])
    except ValueError:
        return None
    if isinstance(data, list):
        data = data[0] if data else None
    return data if isinstance(data, dict) and data.get("id") else None


def actor(root):
    """Who bd records as the claimer, resolved as bd does: $BEADS_ACTOR, git user.name, $USER."""
    if os.environ.get("BEADS_ACTOR"):
        return os.environ["BEADS_ACTOR"]
    try:
        name = subprocess.run(["git", "-C", root, "config", "user.name"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return name or os.environ.get("USER", "")


def claimed_by_me(root, bead):
    """In progress and ours. A bead someone else holds is in progress too, and
    claiming it changed nothing (bd refuses, but `… 2>&1 | tail` hides that)."""
    who = bead.get("assignee")
    return bead.get("status") == "in_progress" and (not who or who == actor(root))


def bind(sid, bead, root):
    b = {"bead": bead["id"], "title": bead.get("title") or "", "root": root,
         "since": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
         "done": bead.get("status") == "closed", "named": None}
    save(sid, b)
    return b


def note_claim(root, bead, worktree):
    """Append new-session's claim note when none names this worktree, so
    end-session (wb-backlog claimed) finds the bead the session is on."""
    if not worktree:
        return None
    want = os.path.realpath(worktree)
    if any(os.path.realpath(w) == want for w in WORKTREE_RE.findall(bead.get("notes") or "")):
        return None
    try:
        branch = subprocess.run(["git", "-C", worktree, "branch", "--show-current"],
                                capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        branch = ""
    note = f"Branch: {branch or '?'} (worktree at {worktree})"
    rc, _ = run_bd(root, ["update", bead["id"], "--append-notes", note], WRITE_TIMEOUT)
    if rc != 0:
        return "bd timed out" if rc is None else f"bd exited {rc}"
    return None


def cut(title):
    return title if len(title) <= TITLE_MAX else title[:TITLE_MAX - 1] + "…"


def segment(stdin_json, env):
    sid = stdin_json.get("session_id") if isinstance(stdin_json, dict) else None
    if not binding_path(sid):
        return ""
    b = load(sid)
    if b and b.get("done"):
        return f"✓ {short(b['bead'])} done · close this session"
    if b:
        return f"◆ {short(b['bead'])} {cut(b.get('title') or '')}".rstrip()
    # WB_SPACE_ROOT is set only on the claude command workbench starts, and the
    # status line inherits it: that is what makes this a workbench session
    return "◇ no bead" if env.get("WB_SPACE_ROOT") else ""


def _segments(cmd):
    """The command split into simple commands, quotes respected: bd text inside
    a quoted description or an echo is one word, not a command."""
    lex = shlex.shlex(cmd, posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"  # newlines separate commands, so they are punctuation here
    lex.whitespace_split = True
    seg = []
    try:
        for tok in lex:
            if tok and set(tok) <= set("();<>|&\n"):
                if seg:
                    yield seg
                seg = []
            else:
                seg.append(tok)
    except ValueError:  # unbalanced quotes: nothing in it can be trusted
        return
    if seg:
        yield seg


def parse(cmd):
    """[("claim", ids) | ("close", ids) | ("create-claim", [])] for each bd
    command in a Bash command line that claims, closes or creates-and-claims."""
    found = []
    for seg in _segments(cmd or ""):
        while seg and re.fullmatch(r"\w+=.*", seg[0]):  # FOO=1 bd …
            seg = seg[1:]
        if len(seg) < 2 or not (seg[0] == "bd" or seg[0].endswith("/bd")):
            continue
        verb, rest = seg[1], seg[2:]
        ids = []
        for t in rest:
            if t.startswith("-"):
                break
            ids.append(t)
        flags = rest[len(ids):]
        claims = "--claim" in flags or "--status=in_progress" in flags or any(
            a in ("--status", "-s") and b == "in_progress" for a, b in zip(flags, flags[1:]))
        if verb == "update" and ids and claims:
            found.append(("claim", ids))
        elif verb == "close" and ids:
            found.append(("close", ids))
        elif verb == "create" and "--claim" in flags:
            found.append(("create-claim", []))
    return found
