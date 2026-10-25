"""wb_touched — when a bead was last touched by anything but grooming.

Grooming may flag a claimed bead (attention add/remove), and any write bumps the bead's
updated_at, which is the only sign of whether a claim is still being worked (bd's started_at
is the first claim ever, kept across a release and re-claim). So a claim's idle age walks
back through grooming's own run records: while the bead's updated_at is a stamp a grooming
write or undo left, the stamp it had before that write is the real last touch.

The records are wb-groom's run dirs, $WB_GROOM_DIR/<space>/<run>/ (lib/wb_groom.py):
before.jsonl and applied.jsonl rows pair up by id and step, and an undone.jsonl row's
`through` counts the applied rows it undid.
"""
import datetime
import glob
import json
import os


def groom_dir():
    return os.environ.get("WB_GROOM_DIR") or os.path.expanduser("~/.local/state/workbench/groom")


def _rows(path):
    """A run file's rows; a missing file or a torn line is just no rows."""
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if isinstance(r, dict) and isinstance(r.get("id"), str):
                    out.append(r)
    except OSError:
        pass
    return out


def grooming_stamps(root, base=None):
    """{(id, stamp grooming left): the stamp the bead had before} for ROOT's beads."""
    want = os.path.realpath(root)
    stamps = {}
    for run in sorted(glob.glob(os.path.join(base or groom_dir(), "*", "*", ""))):
        applied = _rows(os.path.join(run, "applied.jsonl"))
        if not applied or os.path.realpath(str(applied[0].get("root"))) != want:
            continue  # a run dir is one space's, and its rows all carry that root
        before = {(r["id"], r.get("step")): r.get("updated_at") for r in _rows(os.path.join(run, "before.jsonl"))}
        ran = {}
        for r in applied:
            ran.setdefault(r["id"], []).append(r.get("updated_at"))
            was = before.get((r["id"], r.get("step")))
            if r.get("updated_at") and was and was != r["updated_at"]:  # a failed write left it as it was
                stamps[(r["id"], r["updated_at"])] = was
        for r in _rows(os.path.join(run, "undone.jsonl")):
            n = r.get("through")
            mine = ran.get(r["id"], [])
            if (r.get("updated_at") and isinstance(n, int) and 0 < n <= len(mine) and mine[n - 1]
                    and mine[n - 1] != r["updated_at"]):
                stamps[(r["id"], r["updated_at"])] = mine[n - 1]  # undo starts where the last apply left it
    return stamps


def last_touched(bead, stamps):
    """BEAD's updated_at with grooming's own writes walked back."""
    stamp, seen = bead.get("updated_at"), set()
    while stamp and (bead.get("id"), stamp) in stamps and stamp not in seen:
        seen.add(stamp)
        stamp = stamps[(bead.get("id"), stamp)]
    return stamp


def age(stamp, now=None):
    """Whole days from an ISO timestamp to NOW (default: this moment), or None if it isn't one."""
    try:
        t = datetime.datetime.fromisoformat(str(stamp).replace("Z", "+00:00"))
        return ((now or datetime.datetime.now(datetime.timezone.utc)) - t).days
    except (TypeError, ValueError):
        return None
