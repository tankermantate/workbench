"""Is this machine ready for the launcher? The checks wb-doctor prints and wb-setup ends with.

Runs on macOS's own python 3.9 (no tomllib, no 3.10 syntax): telling someone their python is
too old is one of its jobs, so it can't need a newer one to start. Spec:
docs/specs/2026-11-17-guided-setup-design.md

Seams: WB_PYTHON (the python3 the launcher's helpers will get), WB_BD, WB_BIN_DIR,
WORKBENCH_CONFIG, ZDOTDIR, WB_LAUNCH_AGENTS_DIR, WB_DESKTOP_DIR, WB_MCP.
"""
import json
import os
import re
import shutil
import subprocess

import wb_session  # store_root: where bd finds a folder's backlog

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), ".."))
OK, WARN, FAIL = "ok", "--", "!!"
AGENTS = ("workbench.groom", "workbench.restore-save")
TIMEOUT = 15


def home(*p):
    return os.path.join(os.path.expanduser("~"), *p)


def bin_dir():
    return os.environ.get("WB_BIN_DIR") or home(".local", "bin")


def config_path():
    return os.environ.get("WORKBENCH_CONFIG") or home(".config", "workbench", "spaces.toml")


def zshrc():
    return os.path.join(os.environ.get("ZDOTDIR") or os.path.expanduser("~"), ".zshrc")


def zshrc_line():
    return 'source "%s"' % os.path.join(REPO, "shell", "workbench.zsh")


def wb_mcp():
    """wb-mcp (planning in Claude Desktop, gap 1) when this version has it, else None."""
    p = os.environ.get("WB_MCP") or os.path.join(REPO, "bin", "wb-mcp")
    return p if os.path.isfile(p) and os.access(p, os.X_OK) else None


def desktop_config():
    d = os.environ.get("WB_DESKTOP_DIR") or home("Library", "Application Support", "Claude")
    return os.path.join(d, "claude_desktop_config.json")


def run(argv, cwd=None, timeout=TIMEOUT):
    """(rc, stdout, stderr); rc 127 when it can't start, 124 when it hangs."""
    try:
        p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout, p.stderr
    except OSError as e:
        return 127, "", str(e)
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"


def python_version():
    """'3.12' for the python3 the helpers' #!/usr/bin/env python3 finds, or None."""
    py = os.environ.get("WB_PYTHON") or shutil.which("python3")
    if not py:
        return None
    rc, out, _ = run([py, "-c", "import sys; print('%d.%d' % sys.version_info[:2])"])
    return out.strip() if rc == 0 and out.strip() else None


def new_enough(v):
    try:
        return tuple(int(x) for x in v.split(".")[:2]) >= (3, 11)
    except (AttributeError, ValueError):
        return False


def bd_cmd():
    b = os.environ.get("WB_BD") or "bd"
    return shutil.which(b)


def zshrc_has_line():
    """Does ~/.zshrc source a workbench.zsh? Any checkout's counts: this one may be a worktree."""
    try:
        with open(zshrc(), encoding="utf-8") as f:
            return any(re.match(r"\s*(source|\.)\s.*/shell/workbench\.zsh", l) for l in f)
    except OSError:
        return False


def linked():
    """The checkout our commands are linked from (install.sh's job), or None. Any checkout's
    counts: this one may be a worktree of it."""
    t = os.path.realpath(os.path.join(bin_dir(), "wb-spaces"))
    if os.path.basename(os.path.dirname(t)) == "bin" and os.path.isfile(t):
        repo = os.path.dirname(os.path.dirname(t))
        if os.path.isfile(os.path.join(repo, "shell", "workbench.zsh")):
            return repo
    return None


def zshrc_adds_to_path(d):
    """Does ~/.zshrc name D (an earlier wb-setup's PATH line)? This shell may not have read it yet."""
    try:
        with open(zshrc(), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return False
    h = os.path.expanduser("~")
    return d in text or (d.startswith(h + os.sep) and "$HOME" + d[len(h):] in text)


def on_path(d):
    d = os.path.realpath(d)
    return any(os.path.realpath(p) == d for p in os.environ.get("PATH", "").split(os.pathsep) if p)


def spaces():
    """(rows, error, skipped): wb-spaces' rows as dicts, or its reason it can't give them; and
    the spaces it skipped because their root isn't a folder, as (name, why)."""
    rc, out, err = run([os.path.join(REPO, "bin", "wb-spaces")])
    if rc != 0:
        return None, (err.strip().splitlines() or ["wb-spaces failed"])[-1].replace("workbench: ", ""), []
    skipped = []
    for line in err.splitlines():
        # wb-spaces' own note: "workbench: skipping 'Alpha': /x is not a folder"
        if line.startswith("workbench: skipping '") and "': " in line:
            skipped.append(tuple(line[len("workbench: skipping '"):].split("': ", 1)))
    rows = []
    for line in out.splitlines():
        f = line.split("\t")
        if len(f) >= 7:
            rows.append({"label": f[0], "group": "" if f[1] == "-" else f[1], "root": f[2],
                         "beads": f[3], "worktrees": f[4] == "1", "space_key": f[6],
                         "claude_config": "" if len(f) < 8 or f[7] == "-" else f[7]})
    return rows, None, skipped


def desktop_connected():
    try:
        with open(desktop_config(), encoding="utf-8") as f:
            return "workbench" in (json.load(f).get("mcpServers") or {})
    except (OSError, ValueError, AttributeError):
        return False


def checks():
    """Every check, as (level, text)."""
    out = []
    v = python_version()
    if v is None:
        out.append((FAIL, "python3: not found; brew install python"))
    elif not new_enough(v):
        out.append((FAIL, "python3 %s: workbench needs 3.11 or later: brew install python" % v))
    else:
        out.append((OK, "python3 %s" % v))
    rc, gv, _ = run(["git", "--version"])
    out.append((OK, gv.strip()) if rc == 0 else (FAIL, "git: not working; xcode-select --install"))
    out.append((OK, "claude (Claude Code)") if shutil.which("claude") else
               (FAIL, "claude: not found; install Claude Code (https://docs.claude.com/en/docs/claude-code), "
                      "then run claude once to sign in"))
    bd = bd_cmd()
    if not bd:
        out.append((FAIL, "bd: not found; install beads: brew install beads"))
    else:
        rc, bv, err = run([bd, "version"])
        out.append((OK, "bd " + (bv.strip().split("\n")[0].replace("bd version ", "") or "installed"))
                   if rc == 0 else (FAIL, "bd: doesn't run (%s)" % (err.strip() or "exit %d" % rc)))
    out.append((OK, "fzf") if shutil.which("fzf") else
               (WARN, "fzf: not found (optional: searchable menus): brew install fzf"))

    if linked():
        out.append((OK, "commands linked into %s (from %s)" % (bin_dir(), linked())))
        if not on_path(bin_dir()) and not zshrc_adds_to_path(bin_dir()):
            out.append((WARN, "%s is not on your PATH (the launcher works; typing new-session, wb-tabs "
                              "and friends needs it): run wb-setup" % bin_dir()))
    else:
        out.append((FAIL, "commands: not linked into %s; run %s/install.sh" % (bin_dir(), REPO)))
    out.append((OK, "~/.zshrc starts the launcher") if zshrc_has_line() else
               (FAIL, "~/.zshrc doesn't start the launcher; run wb-setup (or add: %s)" % zshrc_line()))
    agents = os.environ.get("WB_LAUNCH_AGENTS_DIR") or home("Library", "LaunchAgents")
    if all(os.path.isfile(os.path.join(agents, a + ".plist")) for a in AGENTS):
        out.append((OK, "schedule: session snapshot and weekly grooming"))
    else:
        out.append((WARN, "schedule: not installed (optional: restore after a restart, weekly grooming): "
                          "%s/install.sh" % REPO))

    path = config_path()
    if not os.path.exists(path):
        out.append((FAIL, "spaces.toml: none at %s; run wb-setup" % path))
    else:
        rows, err, skipped = spaces()
        if rows is None:
            out.append((FAIL, "spaces.toml: %s" % err))
        else:
            n = len(rows) + len(skipped)
            out.append((OK, "spaces.toml: %d space%s" % (n, "" if n == 1 else "s")))
            out.extend(space_check(r) for r in rows)
            # the launcher only skips these, with a note; here they are something to fix
            out.extend((FAIL, "%s: %s" % s) for s in skipped)

    mcp = wb_mcp()
    if not mcp:
        out.append((WARN, "Claude Desktop: planning in Claude (wb-mcp) isn't in this version; wb-update brings it"))
    elif desktop_connected():
        out.append((OK, "Claude Desktop: connected (wb-mcp check says which spaces it sees)"))
    else:
        out.append((WARN, "Claude Desktop: not connected; wb-mcp connect (quit Desktop first)"))
    return out


def space_check(r):
    name = r["label"] if not r["group"] else "%s/%s" % (r["group"], r["label"])
    has = wb_session.store_root(r["root"]) is not None
    if r["beads"] == "true" and not has:
        return (FAIL, "%s: no backlog yet: cd %s && bd init" % (name, r["root"]))
    if r["worktrees"] and run(["git", "-C", r["root"], "rev-parse", "--git-dir"])[0] != 0:
        return (FAIL, "%s: worktrees = true, but %s is not a git repository" % (name, r["root"]))
    return (OK, "%s%s" % (name, "" if has else " (no backlog)"))


def report(results, write=print):
    for level, text in results:
        write("  %-4s %s" % (level, text))
    bad = sum(1 for level, _ in results if level == FAIL)
    if bad:
        write("%d thing%s to fix (the !! lines)." % (bad, "" if bad == 1 else "s"))
    else:
        write("workbench is ready.")
    return 1 if bad else 0
