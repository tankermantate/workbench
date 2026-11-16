"""Which Claude sessions are live, and Claude's own record of each: shared by wb-tabs,
wb-restore and wb-tidy. Reads ps (WB_PS fakes it) and <claude config>/sessions/<pid>.json, nothing else.
Spec: docs/specs/2026-11-05-tabs-view-design.md
"""
import json
import os
import subprocess

PS = os.environ.get("WB_PS", "ps")


def processes():
    """(pid, ppid, tty, command name) for everything on a tty, or None when ps fails."""
    try:
        p = subprocess.run([PS, "-axo", "pid=,ppid=,tty=,comm="], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode:
        return None
    found = []
    for line in p.stdout.splitlines():
        f = line.split(None, 3)
        if len(f) == 4 and f[0].isdigit() and f[1].isdigit() and f[2][0] not in "?-":
            found.append((int(f[0]), int(f[1]), f[2], os.path.basename(f[3].strip())))
    return found


def tabs(procs):
    """{tty: the pid of its session's claude, or None}. The outermost claude is the session:
    it may have spawned another, as a grooming judge or a subagent."""
    claudes = {pid for pid, _, _, comm in procs if comm == "claude"}
    live = {tty: None for _, _, tty, _ in procs}
    for pid, ppid, tty, _ in sorted(procs):
        if pid in claudes and ppid not in claudes and live[tty] is None:
            live[tty] = pid
    return live


def config_dirs(space_rows):
    dirs = [os.path.expanduser("~/.claude"), os.environ.get("CLAUDE_CONFIG_DIR", "")]
    dirs += [os.path.expanduser(r[7]) for r in space_rows if len(r) > 7 and r[7] != "-"]
    return list(dict.fromkeys(d for d in dirs if d))


def pid_file(pid, dirs):
    """Claude's own record of a live pid, or None. "_dir" names the config dir it was found in,
    which is the session's account. Internal to Claude Code and undocumented, so
    any surprise in it means "don't know". In two config dirs, the newest start wins: a pid gets
    reused, and a session that crashed left its file behind."""
    found = []
    for d in dirs:
        try:
            with open(os.path.join(d, "sessions", f"{pid}.json")) as f:
                j = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(j, dict) and j.get("pid") == pid and isinstance(j.get("sessionId"), str):
            found.append(dict(j, _dir=d))
    return max(found, key=lambda j: j.get("startedAt") if isinstance(j.get("startedAt"), (int, float)) else 0,
               default=None)


def sessions(space_rows, unknown=None):
    """[(pid, Claude's pid file)] for each tab's outermost claude, or None when ps fails. The pids
    of claudes with no pid file in any known config dir are appended to `unknown`, if given."""
    procs = processes()
    if procs is None:
        return None
    dirs = config_dirs(space_rows)
    found = []
    for pid in sorted(p for p in tabs(procs).values() if p):
        j = pid_file(pid, dirs)
        if j:
            found.append((pid, j))
        elif unknown is not None:
            unknown.append(pid)
    return found
