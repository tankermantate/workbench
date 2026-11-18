"""wb_groom — the plan reader and the grooming policy, as pure functions.

The judge (Claude) writes decisions.json; plan_ops() turns it into what workbench may apply
by itself (ops), what waits for review (proposals) and what it refused (dropped). Nothing
here writes to bd; bin/wb-groom does the reading, and apply_ops/undo_run below the writing.
judge_argv/run_judge (at the end) start the judge with its read-only allowlist.
"""
import dataclasses
import datetime
import json
import os
import re
import shlex
import shutil
import signal
import sys
import subprocess
import uuid

import wb_touched

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
    protected_known: bool = True  # False when protected.md could not be read


@dataclasses.dataclass
class Op:
    id: str
    kind: str  # wave | unwave | icebox | attention | unattention
    value: str  # wave: the label to be in; unwave: the label to drop; icebox/attention: the label
    why: str


class BdReadError(Exception):
    pass


def _read(path):
    """The file's text, or None when it is missing or unreadable."""
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return None


def read_plan(plan_dir):
    """The Plan in PLAN_DIR, or None when there is no such directory."""
    if not os.path.isdir(plan_dir):
        return None
    goals = _read(os.path.join(plan_dir, "goals.md")) or ""
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
    protected = _read(os.path.join(plan_dir, "protected.md"))
    labels = {l.strip().strip("`") for m in LABELS_RE.findall(protected or "") for l in m.split(",")} - {""}
    return Plan(plan_dir, goals_date, sizes["now"], sizes["next"], labels, protected is not None)


def load_plan(space):
    root = os.environ.get("WB_PLANS_DIR") or os.path.expanduser("~/.config/workbench/plans")
    return read_plan(os.path.join(root, space))


def plan_state(plan, today):
    """missing | stale | ok | due. Both missing and stale fail closed."""
    if plan is None or plan.goals_date is None or not plan.protected_known:
        return "missing"  # without protected.md nothing can be judged protected
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


def _json_list(stdout):
    """The JSON list in bd's STDOUT (it can print 'Warning: …' lines first), or None."""
    start = re.search(r"^\[", stdout, re.M)
    try:
        data = json.loads(stdout[start.start():]) if start else None
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, list) else None


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
    data = _json_list(p.stdout)
    if data is None or not all(isinstance(b, dict) and isinstance(b.get("id"), str) for b in data):
        raise BdReadError("bd list did not return a list of beads")
    return {b["id"]: b for b in data}


BACKLOG = "backlog.tsv"  # in the judge's dir: `bd list --json` of a big store is too long to read


def write_backlog(path, beads, end):
    """Write PATH: every live (not closed) bead of BEADS on one line, priority then id, for the
    judge to read whole (`bd show` gives the detail), and a last line `# end END N beads`, whose
    marker the judge echoes to show it read to the end. Returns N. Raises OSError."""
    def key(b):
        p = b.get("priority")
        return (p if isinstance(p, int) else 9, natural(b["id"]))
    live = sorted((b for b in beads.values() if b.get("status") != "closed"), key=key)
    rows = ["# id\tstatus\tpriority\tupdated\tlabels\ttitle"]
    for b in live:
        cells = [b["id"], b.get("status") or "-", f"P{b.get('priority')}", str(b.get("updated_at") or "-")[:10],
                 ",".join(str(l) for l in b.get("labels") or []) or "-", b.get("title") or ""]
        rows.append("\t".join(" ".join(str(c).split()) for c in cells))  # a tab or newline can't split a row
    rows.append(f"# end {end} {len(live)} beads")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")
    return len(live)


def natural(id):
    """acme-9 before acme-10."""
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", id)]


def read_gap(decisions, expected):
    """Why DECISIONS don't show the judge read backlog.tsv to its end (EXPECTED: {end, beads}),
    or None when they do."""
    got = decisions.get("backlog")
    if not isinstance(got, dict):
        return "the judge did not confirm it read the whole backlog"
    if got.get("end") != expected["end"]:
        return "the judge's end marker does not match backlog.tsv's: it did not read to the end"
    if got.get("beads") != expected["beads"]:
        return f"the judge counted {got.get('beads')} beads, not {expected['beads']}"
    return None


def read_line(decisions, expected):
    """The summary's line on how much of the backlog the judge read: workbench's check of the
    end marker, not the judge's own say."""
    n = expected["beads"]
    if read_gap(decisions, expected) is None:
        return f"The judge read all {n} live beads (backlog.tsv to its end marker)"
    return f"The judge did not show it read all {n} live beads: beads it never saw were not judged"


def backlog_gaps(decisions, beads, expected):
    """Why the judge's DECISIONS don't show it judged the whole backlog, as short lines (none
    when they do). EXPECTED is {end, beads} from write_backlog: the judge must echo both in
    decisions.backlog. And when it sets a sprint section, every unclaimed bead now in that wave
    must be named in now, next or leaving: one it left out is one it most likely never saw."""
    gaps = [g for g in [read_gap(decisions, expected)] if g]
    sprint = decisions.get("sprint")
    if isinstance(sprint, dict):
        named = {e.get("id") for k in ("now", "next", "leaving") if isinstance(sprint.get(k), list)
                 for e in sprint[k] if isinstance(e, dict)}
        set_waves = {WAVES[k] for k in ("now", "next") if k in sprint}
        missed = sorted((id for id, b in beads.items() if b.get("status") not in (CLAIMED, "closed")
                         and set(_wave_labels(b)) & set_waves and id not in named), key=natural)
        if missed:
            gaps.append(f"the sprint leaves out {', '.join(missed)} (in a wave now, named in none of now, next, leaving)")
    return gaps


def claims_line(beads, stamps, today):
    """The judge's CLAIMS: each claimed bead and the whole days since it was last touched,
    grooming's own writes aside (lib/wb_touched.py). The judge would otherwise read updated_at,
    which an attention flag bumps, and a stale claim would drop off its release list."""
    out = []
    for id in sorted(i for i, b in beads.items() if b.get("status") == CLAIMED):
        stamp = wb_touched.last_touched(beads[id], stamps)
        try:
            days = (today - datetime.datetime.fromisoformat(str(stamp).replace("Z", "+00:00")).date()).days
        except (TypeError, ValueError):
            days = None
        out.append(f"{id} {days}d" if days is not None else f"{id} ?")
    return ", ".join(out) or "none"


def _entries(value):
    """A sprint/attention list of (id, why, protected) from {id, why[, protected]} dicts,
    or None when it is the wrong shape. protected is True, False or None (no verdict)."""
    if not isinstance(value, list):
        return None
    out = []
    for e in value:
        if not isinstance(e, dict) or not isinstance(e.get("id"), str):
            return None
        why = e.get("why", "")
        flag = e.get("protected")
        if not isinstance(why, str) or not (flag is None or isinstance(flag, bool)):
            return None
        out.append((e["id"], why, flag))
    return out


def _wave_labels(bead):
    return [l for l in (bead.get("labels") or []) if l in WAVES.values()]


def plan_ops(decisions, beads, plan, today, partial=False):
    """(ops, proposals, dropped) from the judge's DECISIONS and the live BEADS (by id).

    Proposals are numbered by position (1-based) in review: sprint-derived first, then
    changes in decisions order, then attention. A missing or stale plan, or a PARTIAL run (the
    judge did not show it read the whole backlog: backlog_gaps), turns every op into a proposal."""
    state = plan_state(plan, today)
    blocked = (f"plan {state}" if state in ("missing", "stale")
               else "backlog not fully read" if partial else None)
    ops, proposals, dropped = [], [], []

    def propose(id, kind, to, why, reason):
        proposals.append({"id": id, "kind": kind, "to": to, "why": why, "reason": reason})

    def apply(op):
        if blocked:
            propose(op.id, op.kind, op.value, op.why, blocked)
        else:
            ops.append(op)

    def usable(id, claimed_ok=False):
        """The bead for ID, or None after recording why not."""
        b = beads.get(id)
        if b is None:
            dropped.append(f"{id}: unknown id")
        elif b.get("status") == CLAIMED and not claimed_ok:
            dropped.append(f"{id}: claimed")  # work in hand; the judge lists stale claims for review
        elif b.get("status") == "closed":
            dropped.append(f"{id}: closed")
        else:
            return b
        return None

    # A bead may leave the sprint or move away from NOW unattended only with a positive
    # `protected: false` from the judge (a sprint entry or a validated change) and no
    # protected label; silence counts as unsure, so it is a proposal.
    verdicts = {}

    def sprint_protected(id, b):
        v = verdicts.get(id, [])
        return is_protected(b, False if v and all(f is False for f in v) else None, plan)

    changes = decisions.get("changes")
    if changes is not None and not isinstance(changes, list):
        dropped.append("changes: bad field changes")
        changes = []
    valid = []  # (id, kind, to, why, flag), in decisions order
    for c in changes or []:
        if not isinstance(c, dict) or not isinstance(c.get("id"), str):
            dropped.append("changes: bad entry")
            continue
        id, kind, why, to = c["id"], c.get("kind"), c.get("why", ""), c.get("to", "")
        flag = c.get("protected")
        bad = next((f for f, ok in (("kind", isinstance(kind, str) and kind in CHANGE_KINDS),
                                    ("why", isinstance(why, str)), ("to", isinstance(to, str)),
                                    ("protected", flag is None or isinstance(flag, bool))) if not ok), None)
        if bad:
            dropped.append(f"{id}: bad field {bad}")
            continue
        valid.append((id, kind, to, why, flag))
        verdicts.setdefault(id, []).append(flag)

    # --- sprint ---
    sprint = decisions.get("sprint")
    if sprint is not None and not isinstance(sprint, dict):
        dropped.append("sprint: bad field sprint")
        sprint = {}
    sprint = sprint or {}
    sizes = {"now": plan.now_size if plan else DEFAULT_SIZES["now"],
             "next": plan.next_size if plan else DEFAULT_SIZES["next"]}
    leaving = {}  # id -> why, for beads the judge says leave the sprint
    if "leaving" in sprint:
        entries = _entries(sprint["leaving"])
        if entries is None:
            dropped.append("sprint.leaving: bad field leaving")
        for id, why, flag in entries or []:
            if usable(id) is not None:
                leaving[id] = why
                verdicts.setdefault(id, []).append(flag)
    seen, kept = set(), {}  # kept: section -> ids accepted into it
    for section in ("now", "next"):
        if section not in sprint:
            continue
        entries = _entries(sprint[section])
        if entries is None:
            dropped.append(f"sprint.{section}: bad field {section}")
            continue  # and don't unwave that wave's beads on the strength of a list we can't read
        kept[section] = set()
        label, rank = WAVES[section], int(WAVES[section][-1])
        for id, why, flag in entries:
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
            verdicts.setdefault(id, []).append(flag)
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
            if id not in leaving:
                # Named nowhere, so most likely never read (backlog_gaps makes the run partial):
                # a removal on no reason is what the owner once had to catch by hand.
                dropped.append(f"{id}: not judged (named in none of now, next, leaving); keeps {label}")
                continue
            why = leaving[id] or "leaves the sprint (the judge gave no why)"
            if sprint_protected(id, b):
                propose(id, "unwave", label, why, "protected")
            else:
                apply(Op(id, "unwave", label, why))

    # --- changes ---
    for id, kind, to, why, flag in valid:
        b = usable(id)
        if b is None:
            continue
        if kind != "icebox":
            propose(id, kind, to, why, blocked or "always proposed")
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
        for id, why, _ in entries:
            # a claim is work in hand, but a stale one on something due is exactly what the
            # flag is for; a label and an appended note leave the claim itself alone
            b = usable(id, claimed_ok=True)
            if b is None:
                continue
            if (ATTENTION in (b.get("labels") or [])) == (kind == "attention"):
                continue  # already as asked
            apply(Op(id, kind, ATTENTION, why))
    return ops, proposals, dropped


# --- applying and undoing ---
# Everything below writes to a bead store, unattended. The rules: record a bead's state before
# touching it (fsynced), pass --sandbox so bd never auto-pushes, build argv lists (no shell, so
# a hostile `why` is just a string), and read each bead back so undo can tell if anyone else
# has changed it since.

BY_HAND = {"merge", "dep", "date"}  # proposal kinds that are not a single-bead edit
# defer_until, closed_at and close_reason: undefer drops the date and close stamps the others, so
# an exact undo has to see them (bd clears closed_at/close_reason itself when the status leaves
# closed, and takes --defer=<date> to bring a deferral back).
STATE_KEYS = ("labels", "priority", "status", "notes", "defer_until", "closed_at", "close_reason", "updated_at")


class WriteError(Exception):
    pass


def bd_show(root, bd, id, timeout=30):
    """The bead ID as bd shows it (list leaves out notes). Raises BdReadError."""
    try:
        p = subprocess.run([bd, "show", id, "--json"], cwd=root, text=True,
                           capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise BdReadError(f"bd show {id} failed: {e}")
    data = _json_list(p.stdout) if p.returncode == 0 else None
    if not data or not isinstance(data[0], dict) or data[0].get("id") != id:
        raise BdReadError(f"bd show {id} exited {p.returncode}: {p.stderr.strip() or 'no bead'}")
    return data[0]


def snapshot(bead):
    """What a record keeps of a bead: the fields apply and undo change, and updated_at."""
    return {"id": bead["id"], "labels": sorted(bead.get("labels") or []), "priority": bead.get("priority"),
            "status": bead.get("status"), "notes": bead.get("notes") or "",
            **{k: bead.get(k) for k in ("defer_until", "closed_at", "close_reason", "updated_at")}}


def append_jsonl(path, rows):
    """Append ROWS to PATH and fsync the file and its directory: a record that
    must survive whatever happens next."""
    with open(path, "a", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")
        f.flush()
        os.fsync(f.fileno())
    fd = os.open(os.path.dirname(os.path.abspath(path)), os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def read_jsonl(path):
    try:
        with open(path, encoding="utf-8") as f:
            return [json.loads(l) for l in f if l.strip()]
    except FileNotFoundError:
        return []


def _line(text):
    return " ".join(str(text).split())  # one line per note, whatever the why held


def edit_for(ops, labels, today):
    """What one bead's OPS (all of them, in order) come to against its current LABELS:
    (add, remove, priority, notes, commands). commands are extra bd verbs: close, undefer."""
    now, priority, notes, commands, reason = set(labels), None, [], [], ""
    for o in ops:
        if o.kind == "wave":
            now -= set(WAVES.values())
            now.add(o.value)
        elif o.kind in ("unwave", "unattention"):
            now.discard(o.value)
        elif o.kind in ("icebox", "attention"):
            now.add(o.value)
        elif o.kind == "priority":
            priority = o.value
        elif o.kind in ("close", "undefer"):
            commands.append(o.kind)
            reason = _line(o.why)
        notes.append(f"groomed {today}: {o.kind} \u2014 {_line(o.why)}")
        if o.kind == "attention":
            notes.append(f"attention: {_line(o.why)}")
    return sorted(now - set(labels)), sorted(set(labels) - now), priority, notes, commands, reason


def _argvs(bd, id, labels, ops, today):
    add, remove, priority, notes, commands, reason = edit_for(ops, labels, today)
    out = []
    if add or remove or priority is not None or notes:
        a = [bd, "--sandbox", "update", id]
        for l in add:
            a += ["--add-label", l]
        for l in remove:
            a += ["--remove-label", l]
        if priority is not None:
            a += [f"--priority={priority}"]
        if notes:
            a += ["--append-notes", "\n".join(notes)]
        out.append(a)
    for c in commands:
        out.append([bd, "--sandbox", c, id] + ([f"--reason={reason}"] if c == "close" else []))
    return out


def _run(argv, root, timeout):
    try:
        p = subprocess.run(argv, cwd=root, text=True, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return str(e)
    return None if p.returncode == 0 else f"exit {p.returncode}: {p.stderr.strip()}"


def apply_ops(run_dir, root, ops, bd, today, proposal=None, timeout=60):
    """Apply OPS (Op objects, any kind) to ROOT's beads, one bd update per bead. Returns
    (applied ids, failed id or None, error, recorded): recorded is False when the failed bead
    was written but applied.jsonl could not say so (error then holds the manual restore).
    Raises BdReadError before any write when a bead can't be read, and OSError before any
    write when before.jsonl can't be written; nothing raises after the first write."""
    order = list(dict.fromkeys(o.id for o in ops))
    current = {id: bd_show(root, bd, id) for id in order}
    step = uuid.uuid4().hex  # ties this call's before rows to its applied rows, which position cannot
    append_jsonl(os.path.join(run_dir, "before.jsonl"), [{**snapshot(current[id]), "step": step} for id in order])
    applied = []
    for id in order:
        mine = [o for o in ops if o.id == id]
        error = None
        for argv in _argvs(bd, id, current[id].get("labels") or [], mine, today):
            error = _run(argv, root, timeout)
            if error:
                break
        row = {"id": id, "step": step, "root": os.path.abspath(root),
               "ops": [{"kind": o.kind, "value": o.value, "why": o.why} for o in mine],
               "proposal": proposal, "applied_at": datetime.datetime.now().isoformat(timespec="seconds")}
        now = None
        try:
            now = snapshot(bd_show(root, bd, id))
            row.update(now)
        except BdReadError as e:
            row["updated_at"] = None  # unverifiable: undo will refuse it
            error = error or str(e)
        if error:
            row["error"] = error
        try:
            append_jsonl(os.path.join(run_dir, "applied.jsonl"), [row])
        except OSError as e:
            # The write happened and undo can't see it: say so, and hand over the way back.
            restore = " ".join(shlex.quote(a) for a in restore_argv(bd, snapshot(current[id]), now))
            return applied, id, f"written but not recorded ({e}); restore by hand: {restore}", False
        if error:
            return applied, id, error, True
        applied.append(id)
    return applied, None, None, True


def restore_argv(bd, was, now):
    """The bd update argv that takes a bead from NOW (a snapshot, or None when unknown) back
    to WAS, or just [bd, --sandbox, update, id] when there is nothing to change."""
    now = now or {"labels": [], "priority": None, "status": None, "notes": None, "defer_until": None}
    argv = [bd, "--sandbox", "update", was["id"]]
    for l in sorted(set(was["labels"]) - set(now["labels"])):
        argv += ["--add-label", l]
    for l in sorted(set(now["labels"]) - set(was["labels"])):
        argv += ["--remove-label", l]
    if was["priority"] != now["priority"]:
        argv += [f"--priority={was['priority']}"]
    # --defer=<date> also sets the status deferred, so it comes before the status.
    if was.get("defer_until") != now.get("defer_until"):
        argv += [f"--defer={was.get('defer_until') or ''}"]
    if was["status"] != now["status"] or (was.get("defer_until") or None) != (now.get("defer_until") or None):
        argv += [f"--status={was['status']}"]
    if was["notes"] != now["notes"]:
        argv += [f"--notes={was['notes']}"]  # wholesale; an empty value clears them
    return argv


def undo_run(run_dir, root, bd, only=None, timeout=60):
    """Restore beads to their before.jsonl state. Returns (messages, refused): refused is
    True when a named bead was changed since the run, can't be read, isn't in the run or was
    never applied.

    A bead can be applied several times (the full run, then proposals), and a run that
    stopped leaves before rows for beads it never wrote. Rows are paired by `step`, the id of
    the apply call that wrote them: a before row with no applied row of its step wrote
    nothing, so it is never a restore target. Undo goes back to the before row of the first
    apply not yet undone, and only if the bead's rows chain: each before row, applied or not,
    must equal where the previous step left the bead (its applied row, or its own before row
    when nothing was written). A break means someone changed the bead, or a write went
    unrecorded; undo refuses it rather than wipe that."""
    before, applied, through = {}, {}, {}
    for r in read_jsonl(os.path.join(run_dir, "before.jsonl")):
        before.setdefault(r["id"], []).append(r)
    for r in read_jsonl(os.path.join(run_dir, "applied.jsonl")):
        applied.setdefault(r["id"], []).append(r)
    for r in read_jsonl(os.path.join(run_dir, "undone.jsonl")):
        through[r["id"]] = max(through.get(r["id"], 0), r.get("through", 0))  # applies undone so far
    msgs, refused = [], False
    for id in ([only] if only else list(before)):
        ran, k = applied.get(id, []), through.get(id, 0)
        if id not in before:
            msgs.append(f"{id}: not in this run's before.jsonl; skipped")
            refused = True
        elif not ran:
            msgs.append(f"{id}: not applied; skipped")
            refused = refused or bool(only)
        elif k >= len(ran):
            msgs.append(f"{id}: already undone")
        else:
            rows = before[id]
            target = next((i for i, r in enumerate(rows) if r.get("step") == ran[k].get("step")), None)
            if target is None or not _chains(rows[0 if k == 0 else target:], ran):
                msgs.append(f"{id} changed since the run; not undone")
                refused = True
                continue
            ok, msg = _undo_one(run_dir, root, bd, rows[target], ran, timeout)
            msgs.append(msg)
            refused = refused or not ok
    return msgs, refused


def _chains(rows, ran):
    """True when each of the before ROWS starts where the step before it left the bead."""
    left = {r.get("step"): r for r in ran}  # step -> its applied row
    prev = None
    for r in rows:
        if prev is not None and any(snapshot(r)[k] != prev[k] for k in STATE_KEYS):
            return False
        prev = snapshot(left.get(r.get("step"), r))  # no applied row: nothing was written
    return True


def _undo_one(run_dir, root, bd, was, ran, timeout):
    id = was["id"]
    try:
        now = snapshot(bd_show(root, bd, id))
    except BdReadError as e:
        return False, f"{id}: cannot read it ({e}); not undone"
    # updated_at has one-second resolution, so a same-second edit is caught by the fields.
    if ran[-1].get("updated_at") is None or any(now[k] != snapshot(ran[-1])[k] for k in STATE_KEYS):
        return False, f"{id} changed since the run; not undone"
    was = snapshot(was)
    argv = restore_argv(bd, was, now)
    if len(argv) > 4:
        error = _run(argv, root, timeout)
        if error:
            return False, f"{id}: undo failed ({error}); by hand: {' '.join(shlex.quote(a) for a in argv)}"
    try:
        after = snapshot(bd_show(root, bd, id))
    except BdReadError:
        after = None
    append_jsonl(os.path.join(run_dir, "undone.jsonl"),
                 [{"id": id, "through": len(ran), "undone_at": datetime.datetime.now().isoformat(timespec="seconds"),
                   "updated_at": after and after["updated_at"]}])
    off = [k for k in STATE_KEYS if k != "updated_at" and (after is None or after[k] != was[k])]
    if off:
        # bd could not put it back exactly: never say "restored" for that.
        return False, f"{id}: restored, but {', '.join(off)} differ from before; fix by hand"
    return True, f"{id}: restored"


# --- the judge ---
# The judge's allowlist is enforced by Claude Code, not by the prompt (a prompt alone did not keep
# the dry run read-only). Checked by hand with claude 2.1.309 on a throwaway bd store, reading
# permission_denials from --output-format json (task-5-report.md has the probes):
#   --setting-sources ""     is accepted and drops user, project and local settings: a project
#                            .claude/settings.json allowing Bash, Write and Edit and holding a
#                            SessionStart hook had no effect (the hook never ran); auth still works.
#   --permission-mode dontAsk  refuses whatever no rule allows, with no prompt.
#   --tools Bash,Read,Write  the only tools loaded: no Edit, NotebookEdit, WebFetch, WebSearch, Agent.
#   Bash(git:*) in deny      needed: Claude Code auto-allows read-only commands such as `git log`
#                            even under dontAsk (it ran in the first probe); denied, git is refused
#                            alone and inside `bd ... && git log`.
#   Edit(//<dir>/**)         is what lets Write into a dir; a Write(...) rule grants nothing, and
#                            a bare Edit deny blocks Write too, so Edit is not in deny. The dir is
#                            the judge's own, <run dir>/judge: it may write there (nested too),
#                            but not <run dir>/reviewed, before.jsonl or inputs.json, nor read them.
#   `--` before the prompt   --add-dir and --allowedTools are variadic and would take the prompt.
#   Bash(<run dir>/bd-readonly:*)  the one Bash rule (write_judge_bd). `Bash(bd --readonly list:*)`
#                            was not enough: bd's global flags may follow the subcommand
#                            (`--profile` wrote files into the cwd, `--db`/`-C`/`--global` read
#                            other stores, `--readonly=false`), so the script whitelists the args.
# Refused in the probes: git log, git status, `bd ... && git log`, bd itself (with or without
# --readonly), cat or ls outside the working dirs, touch, `... > file`, Write to the space root, the
# plan dir, a path outside, and <dir>/../x; and, with the minimal env (judge_env), every network
# command tried: curl, wget, gh api, gh issue list, ssh, nc, dig, nslookup, host, ping, whois,
# traceroute, plus env, printenv, python3 -c, and around the script: `cd / && <script>`,
# `BEADS_DIR=x <script>`, `<script> show "$(curl …)"`, `<script> …; curl …`. The script itself
# refused --profile, --db, -C, --global and --readonly=false. Allowed: the script's list and show,
# Read in the root and plan dir, Write in the judge's dir; the judge still authenticated.
# dontAsk already refused every one of these in the probe (only git got through, by Claude Code's
# read-only auto-allow); named anyway so a wider auto-allow in a later Claude Code can't let one in.
JUDGE_NET = ("curl", "wget", "gh", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "telnet", "ftp",
             "dig", "nslookup", "host", "ping", "whois", "traceroute", "env", "printenv")
JUDGE_DENY = (["Bash(git:*)"] + [f"Bash({c}:*)" for c in JUDGE_NET]
              + ["NotebookEdit", "WebFetch", "WebSearch"])
JUDGE_BD = "bd-readonly"  # the per-run script in the run dir; lib/wb_judge_bd.py says why
JUDGE_ENV = ("HOME", "USER", "LOGNAME", "LANG", "TMPDIR")  # what bd needs; nothing secret


def write_judge_bd(run_dir, root, bd):
    """Write RUN_DIR/bd-readonly, the judge's only bd, and return its path. Raises OSError."""
    exe = shutil.which(bd)
    if not exe:
        raise OSError(f"{bd} not found on PATH")
    exe = os.path.realpath(exe)
    env = {k: os.environ[k] for k in JUDGE_ENV if k in os.environ}
    env.update({k: v for k, v in os.environ.items() if k.startswith("LC_")})
    env["PATH"] = os.pathsep.join([os.path.dirname(exe), "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
    lib = os.path.dirname(os.path.realpath(__file__))
    path = os.path.join(run_dir, JUDGE_BD)
    # -I: no PYTHONPATH, no user site, not the script's dir, whatever the judge's shell has set.
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"#!{os.path.realpath(sys.executable)} -I\n"
                "import sys\n"
                f"sys.path.insert(0, {lib!r})\n"
                "import wb_judge_bd\n"
                f"sys.exit(wb_judge_bd.main(sys.argv[1:], {os.path.realpath(root)!r}, {exe!r}, {env!r}))\n")
    os.chmod(path, 0o555)
    return path


def judge_rules(judge_bd, root, plan_dir, out_dir):
    """The allow rules: the one bd script JUDGE_BD, Read in ROOT, PLAN_DIR (or None) and OUT_DIR,
    Write in OUT_DIR (the judge's own dir). Paths are absolute rules (`//path`), resolved, since
    the rule is matched against real paths."""
    dirs = [d for d in (root, plan_dir, out_dir) if d]
    return ([f"Bash({os.path.realpath(judge_bd)}:*)"]
            + [f"Read(/{os.path.realpath(d)}/**)" for d in dirs]
            + [f"Edit(/{os.path.realpath(out_dir)}/**)"])


def judge_argv(claude, judge_bd, root, plan_dir, out_dir, prompt):
    """The judge's argv. Never --dangerously-skip-permissions or a mode that skips prompts."""
    allow = judge_rules(judge_bd, root, plan_dir, out_dir)
    settings = json.dumps({"permissions": {"allow": allow, "deny": JUDGE_DENY}})
    dirs = [os.path.realpath(d) for d in (out_dir, plan_dir) if d]
    return [claude, "-p", "--setting-sources", "", "--strict-mcp-config", "--permission-mode", "dontAsk",
            "--tools", "Bash,Read,Write", "--no-session-persistence", "--output-format", "json",
            "--settings", settings, "--allowedTools", *allow, "--add-dir", *dirs, "--", prompt]


def run_judge(argv, cwd, env, timeout, out_path, err_path):
    """(exit code, timed_out). The judge gets its own process group, so a timeout stops it and
    anything it started; its output goes to files, so a leftover child can't hold a pipe open.
    Raises OSError when it can't be started."""
    with open(out_path, "wb") as out, open(err_path, "wb") as err:
        p = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                             start_new_session=True)
        try:
            return p.wait(timeout=timeout), False
        except subprocess.TimeoutExpired:
            _killpg(p.pid, signal.SIGTERM)
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            _killpg(p.pid, signal.SIGKILL)  # whatever in the group ignored SIGTERM
            p.wait()
            return None, True


def _killpg(pgid, sig):
    try:
        os.killpg(pgid, sig)
    except (ProcessLookupError, PermissionError):
        pass  # the group is gone
