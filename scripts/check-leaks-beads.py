#!/usr/bin/env python3
"""check-leaks-beads.py TERMS REPO — the bead-store half of check-leaks.sh.

bd keeps beads in Dolt databases under REPO/.beads and syncs them to the git
remote (refs/dolt/data), so every row and every row's history is published
with a push. Scans current rows, dolt_history_* and commit messages for the
words in TERMS (whole words, any case, like grep -w -i -F), and prints one
line per finding without repeating the word itself.

Exit 0: nothing found. 1: found. 2: couldn't scan (dolt missing or a query
failed). Also prints "remote: <where>" when a git or Dolt remote is set, so
the caller can decide whether a finding is a warning or a refusal.
"""
import glob
import json
import os
import re
import subprocess
import sys

terms_file, repo = sys.argv[1], sys.argv[2]
dolt = os.environ.get("WB_DOLT", "dolt")
terms = [t.strip() for t in open(terms_file) if t.strip()]
# grep -w: a match can't touch a letter, digit or underscore on either side.
pat = re.compile(r"(?<![A-Za-z0-9_])(?:" + "|".join(map(re.escape, terms)) + r")(?![A-Za-z0-9_])", re.I)

dbs = sorted(os.path.dirname(d) for d in glob.glob(os.path.join(repo, ".beads", "**", ".dolt"), recursive=True))
if not dbs:
    sys.exit(0)

def no_push():
    """bd's no-push setting (.beads/config.yaml): bd then never pushes the store to the git
    remote. A Dolt remote is another matter: `bd dolt push` publishes to it either way."""
    try:
        text = open(os.path.join(repo, ".beads", "config.yaml")).read()
    except OSError:
        return False
    return re.search(r"(?m)^no-push:[ \t]*true[ \t]*(#.*)?$", text) is not None


remotes = []
if subprocess.run(["git", "-C", repo, "remote"], capture_output=True, text=True).stdout.strip():
    if no_push():
        print("note: a git remote is set, but bd's no-push is on, so the bead db is not published to it")
    else:
        remotes.append("git")
for db in dbs:
    # Read from disk, not through dolt, so a missing dolt still knows a remote is set.
    try:
        state = json.load(open(os.path.join(db, ".dolt", "repo_state.json")))
    except (OSError, ValueError):
        state = {"remotes": {"?": "unreadable repo_state.json"}}
    if state.get("remotes"):
        remotes.append("dolt (" + os.path.relpath(db, repo) + ")")
if remotes:
    print("remote: " + ", ".join(remotes))


def query(db, sql):
    try:
        r = subprocess.run([dolt, "sql", "-r", "json", "-q", sql], cwd=db, capture_output=True, text=True)
    except OSError as e:
        raise RuntimeError(f"can't run {dolt}: {e.strerror}")
    if r.returncode != 0:
        raise RuntimeError(f"{os.path.relpath(db, repo)}: {sql}: {r.stderr.strip()}")
    out = r.stdout.strip()
    try:
        # An empty result comes back as {} with no "rows".
        return json.loads(out).get("rows", []) if out else []
    except ValueError:
        raise RuntimeError(f"{os.path.relpath(db, repo)}: {sql}: unreadable output")


def hits(rows):
    return [r for r in rows if any(isinstance(v, str) and pat.search(v) for v in r.values())]


found = False
try:
    for db in dbs:
        name = os.path.relpath(db, repo)
        def tables(as_of=""):
            # dolt's json output sorts columns by name, so pick them by name, never by position.
            return [v for r in query(db, f"show full tables {as_of} where Table_type = 'BASE TABLE'")
                    for k, v in r.items() if k.startswith("Tables_in_")]
        branches = [r["name"] for r in query(db, "select name from dolt_branches")]
        # The working set: rows not yet committed are committed (and pushed) later.
        for t in tables():
            cur = hits(query(db, f"select * from `{t}`"))
            if cur:
                found = True
                # The primary key (a bead id for issues) is enough to find the row to fix.
                keys = [r["Column_name"] for r in query(db, f"show keys from `{t}`") if r["Key_name"] == "PRIMARY"]
                ids = ["/".join(str(r[k]) for k in keys) or "?" for r in cur]
                more = f" (+{len(ids) - 10} more)" if len(ids) > 10 else ""
                print(f"bead db: {t} ({name}): {len(cur)} rows: {' '.join(ids[:10])}{more}")
        # History is per branch; scan them all, since a push carries every branch. Only
        # tables committed there have history (dolt_ignore'd ones never do, nor get pushed).
        for b in branches:
            for t in tables(f"as of '{b}'"):
                past = hits(query(db, f"select * from `dolt_history_{t}` as of '{b}'"))
                if past:
                    found = True
                    print(f"bead db: {t} history ({name}, {b}): {len(past)} row versions")
        for b in branches:
            msgs = hits(query(db, f"select commit_hash, committer, email, message from dolt_log as of '{b}'"))
            if msgs:
                found = True
                print(f"bead db: commits ({name}, {b}): {' '.join(r['commit_hash'][:8] for r in msgs)}")
except Exception as e:
    # Anything unexpected is "can't tell", never "found" or "clean": the caller fails closed on it.
    print(f"bead db: can't scan: {e.__class__.__name__}: {e}")
    sys.exit(2)
sys.exit(1 if found else 0)
