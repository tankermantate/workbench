"""wb_groom — the plan reader and the grooming policy, as pure functions.

The judge (Claude) writes decisions.json; plan_ops() turns it into what workbench may apply
by itself (ops), what waits for review (proposals) and what it refused (dropped). Nothing
here writes to bd; bin/wb-groom does the reading and, later, the applying.
"""
import dataclasses
import datetime
import json
import os
import re
import subprocess

WAVES = {"now": "wave:1", "next": "wave:2"}  # sprint section -> label, as in bin/wb-backlog
ICEBOX = "icebox"
ATTENTION = "attention"
CLAIMED = "in_progress"
DEFAULT_SIZES = {"now": 5, "next": 8}
STALE_DAYS = 45  # past this the plan can't be trusted to say what matters
DUE_DAYS = 30  # strategy is due; the plan still applies
# Kinds that are never applied unattended (the spec's "only proposes"), plus icebox,
# which is applied only to an unprotected bead.
CHANGE_KINDS = {"icebox", "priority", "merge", "close", "undefer", "dep", "date"}

DATE_RE = re.compile(r"^[\s>*-]*date:\s*(\d{4}-\d{2}-\d{2})", re.M)
SPRINT_RE = re.compile(r"^[\s>*-]*sprint:\s*(.+)$", re.M)
LABELS_RE = re.compile(r"^[\s>*-]*labels:\s*(.+)$", re.M)


@dataclasses.dataclass
class Plan:
    dir: str
    goals_date: datetime.date | None
    now_size: int = DEFAULT_SIZES["now"]
    next_size: int = DEFAULT_SIZES["next"]
    protected_labels: set = dataclasses.field(default_factory=set)


@dataclasses.dataclass
class Op:
    id: str
    kind: str  # wave | unwave | icebox | attention | unattention
    value: str  # wave: the label to be in; unwave: the label to drop; icebox/attention: the label
    why: str


class BdReadError(Exception):
    pass


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return ""


def read_plan(plan_dir):
    """The Plan in PLAN_DIR, or None when there is no such directory."""
    if not os.path.isdir(plan_dir):
        return None
    goals = _read(os.path.join(plan_dir, "goals.md"))
    m = DATE_RE.search(goals)
    try:
        goals_date = datetime.date.fromisoformat(m.group(1)) if m else None
    except ValueError:
        goals_date = None  # an impossible date reads as no date: fail closed
    sizes = dict(DEFAULT_SIZES)
    m = SPRINT_RE.search(goals)
    if m:
        for key, n in re.findall(r"\b(now|next)\s*=\s*(\d+)", m.group(1)):
            if int(n) > 0:
                sizes[key] = int(n)
    m = LABELS_RE.search(_read(os.path.join(plan_dir, "protected.md")))
    labels = {l.strip().strip("`") for l in m.group(1).split(",")} - {""} if m else set()
    return Plan(plan_dir, goals_date, sizes["now"], sizes["next"], labels)


def load_plan(space):
    root = os.environ.get("WB_PLANS_DIR") or os.path.expanduser("~/.config/workbench/plans")
    return read_plan(os.path.join(root, space))


def plan_state(plan, today):
    """missing | stale | ok | due. Both missing and stale fail closed."""
    if plan is None or plan.goals_date is None:
        return "missing"
    age = (today - plan.goals_date).days
    if age > STALE_DAYS:
        return "stale"
    return "due" if age >= DUE_DAYS else "ok"


def is_protected(bead, decision_protected, plan):
    """Protected by label, or unless the judge positively says it is not (None = unsure)."""
    labels = set(bead.get("labels") or [])
    if plan is not None and labels & plan.protected_labels:
        return True
    return decision_protected is not False


def read_beads(root, bd="bd", timeout=30):
    """Every bead bd lists in ROOT, by id. Raises BdReadError: a half-read store must not
    look like one where the named beads don't exist."""
    try:
        p = subprocess.run([bd, "list", "-n", "0", "--json"], cwd=root, text=True,
                           capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise BdReadError(f"bd list failed: {e}")
    if p.returncode != 0:
        raise BdReadError(f"bd list exited {p.returncode}: {p.stderr.strip()}")
    start = re.search(r"^\[", p.stdout, re.M)  # bd can print 'Warning: …' lines first
    try:
        data = json.loads(p.stdout[start.start():]) if start else None
    except json.JSONDecodeError:
        data = None
    if not isinstance(data, list) or not all(isinstance(b, dict) and isinstance(b.get("id"), str) for b in data):
        raise BdReadError("bd list did not return a list of beads")
    return {b["id"]: b for b in data}


def _entries(value):
    """A sprint/attention list of {id, why} dicts, or None when it is the wrong shape."""
    if not isinstance(value, list):
        return None
    out = []
    for e in value:
        if not isinstance(e, dict) or not isinstance(e.get("id"), str):
            return None
        why = e.get("why", "")
        if not isinstance(why, str):
            return None
        out.append((e["id"], why))
    return out


def _wave_labels(bead):
    return [l for l in (bead.get("labels") or []) if l in WAVES.values()]


def plan_ops(decisions, beads, plan, today):
    """(ops, proposals, dropped) from the judge's DECISIONS and the live BEADS (by id).

    Proposals are numbered by position (1-based) in review: sprint-derived first, then
    changes in decisions order, then attention. A missing or stale plan turns every op
    into a proposal."""
    state = plan_state(plan, today)
    blocked = state in ("missing", "stale")
    ops, proposals, dropped = [], [], []

    def propose(id, kind, to, why, reason):
        proposals.append({"id": id, "kind": kind, "to": to, "why": why, "reason": reason})

    def apply(op):
        if blocked:
            propose(op.id, op.kind, op.value, op.why, f"plan {state}")
        else:
            ops.append(op)

    def usable(id):
        """The bead for ID, or None after recording why not."""
        b = beads.get(id)
        if b is None:
            dropped.append(f"{id}: unknown id")
        elif b.get("status") == CLAIMED:
            dropped.append(f"{id}: claimed")  # work in hand; the judge lists stale claims for review
        elif b.get("status") == "closed":
            dropped.append(f"{id}: closed")
        else:
            return b
        return None

    # The judge rules on protection only in `changes`. A sprint move of a bead it said
    # nothing about is judged by the plan's labels alone; a bead it called unsure or
    # protected there stays protected here too.
    flags = {}
    for c in decisions.get("changes") if isinstance(decisions.get("changes"), list) else []:
        if isinstance(c, dict) and isinstance(c.get("id"), str):
            flags.setdefault(c["id"], []).append(c.get("protected"))

    def sprint_protected(id, b):
        return is_protected(b, False if all(f is False for f in flags.get(id, [])) else None, plan)

    # --- sprint ---
    sprint = decisions.get("sprint")
    if sprint is not None and not isinstance(sprint, dict):
        dropped.append("sprint: bad field sprint")
        sprint = None
    sizes = {"now": plan.now_size if plan else DEFAULT_SIZES["now"],
             "next": plan.next_size if plan else DEFAULT_SIZES["next"]}
    seen, kept = set(), {}  # kept: section -> ids accepted into it
    for section in ("now", "next"):
        if sprint is None or section not in sprint:
            continue
        entries = _entries(sprint[section])
        if entries is None:
            dropped.append(f"sprint.{section}: bad field {section}")
            continue  # and don't unwave that wave's beads on the strength of a list we can't read
        kept[section] = set()
        label, rank = WAVES[section], int(WAVES[section][-1])
        for id, why in entries:
            if id in seen:
                dropped.append(f"{id}: duplicate")
                continue
            seen.add(id)
            b = usable(id)
            if b is None:
                continue
            if len(kept[section]) >= sizes[section]:
                dropped.append(f"{id}: over size")
                continue
            kept[section].add(id)
            current = _wave_labels(b)
            if current == [label]:
                continue
            note = f"{section.upper()}: {why}" if why else section.upper()
            # Adding to NOW/NEXT is safe; moving a protected bead further from NOW is not.
            demotes = bool(current) and min(int(l[-1]) for l in current) < rank
            if demotes and sprint_protected(id, b):
                propose(id, "wave", label, why, "protected")
            else:
                apply(Op(id, "wave", label, note))
    for id, b in beads.items():
        for label in _wave_labels(b):
            section = "now" if label == WAVES["now"] else "next"
            if section not in kept or b.get("status") in (CLAIMED, "closed"):
                continue
            if any(id in ids for ids in kept.values()):
                continue  # named in a section: its wave op (or its no-op) settles the wave
            if sprint_protected(id, b):
                propose(id, "unwave", label, "left the sprint", "protected")
            else:
                apply(Op(id, "unwave", label, "left the sprint"))

    # --- changes ---
    changes = decisions.get("changes")
    if changes is not None and not isinstance(changes, list):
        dropped.append("changes: bad field changes")
        changes = []
    for c in changes or []:
        if not isinstance(c, dict) or not isinstance(c.get("id"), str):
            dropped.append("changes: bad entry")
            continue
        id, kind, why, to = c["id"], c.get("kind"), c.get("why", ""), c.get("to", "")
        flag = c.get("protected")
        bad = next((f for f, ok in (("kind", kind in CHANGE_KINDS), ("why", isinstance(why, str)),
                                    ("to", isinstance(to, str)),
                                    ("protected", flag is None or isinstance(flag, bool))) if not ok), None)
        if bad:
            dropped.append(f"{id}: bad field {bad}")
            continue
        b = usable(id)
        if b is None:
            continue
        if kind != "icebox":
            propose(id, kind, to, why, "plan " + state if blocked else "always proposed")
        elif ICEBOX in (b.get("labels") or []):
            continue
        elif is_protected(b, flag, plan):
            propose(id, kind, to, why, "protected")
        else:
            apply(Op(id, "icebox", ICEBOX, why))

    # --- attention ---
    attention = decisions.get("attention")
    if attention is not None and not isinstance(attention, dict):
        dropped.append("attention: bad field attention")
        attention = None
    for key, kind in (("add", "attention"), ("remove", "unattention")):
        if attention is None or key not in attention:
            continue
        entries = _entries(attention[key])
        if entries is None:
            dropped.append(f"attention.{key}: bad field {key}")
            continue
        for id, why in entries:
            b = usable(id)
            if b is None:
                continue
            if (ATTENTION in (b.get("labels") or [])) == (kind == "attention"):
                continue  # already as asked
            apply(Op(id, kind, ATTENTION, why))
    return ops, proposals, dropped
