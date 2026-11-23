"""Making a new space: the steps, with no prompts (wb-new-space asks; a chat tool can call it too).

wb-setup imports the config-writing pieces from here, so the two can't drift. wb-setup runs on
macOS's python 3.9, so this module stays 3.9-safe: no tomllib, no 3.10+ syntax. The config is
read back only through bin/wb-spaces, which has the right python.
"""
import json
import os
import re
import shlex
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import wb_doctor  # noqa: E402

HEADER = """# workbench's spaces: one [[space]] per project folder the launcher offers. wb-setup wrote this;
# edit it by hand any time (wb-doctor checks it). Every key is explained in
# %s

[launcher]
# $TERM_PROGRAM values, besides Apple_Terminal, that should auto-start the launcher.
terminals = []
"""


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "space"


def bead_prefix(name):
    """A prefix bd init accepts for this name. bd otherwise names its database after the folder,
    and refuses one that isn't letters, digits, _ and -, or doesn't start with a letter or _."""
    p = slug(name)
    return p if p[0].isalpha() else "p-" + p


def unique_key(name, taken):
    k, n = slug(name), 2
    while k in taken:
        k, n = "%s-%d" % (slug(name), n), n + 1
    return k


def tilde(p):
    h = os.path.expanduser("~")
    return "~" + p[len(h):] if p == h or p.startswith(h + os.sep) else p


def toml_str(s):
    # a JSON string is a TOML basic string: same escapes for quotes, backslashes and controls
    return json.dumps(s, ensure_ascii=False)


def space_toml(s):
    out = ["[[space]]", "name = %s" % toml_str(s["name"]), "root = %s" % toml_str(tilde(s["root"])),
           "beads = %s" % ("true" if s["beads"] == "true" else toml_str(s["beads"])),
           "worktrees = %s" % ("true" if s["worktrees"] else "false")]
    if s["worktrees"]:
        out.append("space_key = %s" % toml_str(s["space_key"]))
    if s.get("claude_config"):
        out.append("claude_config = %s" % toml_str(tilde(s["claude_config"])))
    return "\n".join(out) + "\n"


def append_spaces(path, new, header_ref):
    """Append the new [[space]]s to spaces.toml and read it back through wb-spaces. (ok, why not).
    Fails closed: when it doesn't read back, the file goes back to what it was."""
    before = None
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            before = f.read()
    text = (before.rstrip("\n") + "\n" if before else HEADER % header_ref)
    text += "".join("\n" + space_toml(s) for s in new)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(path + ".tmp", path)
    got, err, _ = wb_doctor.spaces()
    if got is None:
        if before is None:
            os.remove(path)
        else:
            with open(path, "w", encoding="utf-8") as f:
                f.write(before)
        return False, err
    return True, ""


def init_backlog(folder, extra=()):
    """bd init in folder. (ok, its output)."""
    bd = wb_doctor.bd_cmd()
    if not bd:
        return False, "bd not found"
    rc, out, err = wb_doctor.run([bd, "init", "--non-interactive"] + list(extra), cwd=folder, timeout=300)
    return rc == 0, out + err


# --- making one ---

KINDS = ("idea", "tool")
TEMPLATE = os.path.join(os.path.dirname(os.path.realpath(__file__)), "new-space-templates", "CLAUDE.md")


def default_parent():
    return os.path.abspath(os.path.expanduser(os.environ.get("WB_NEW_SPACE_PARENT") or "~/dev"))


def areas():
    """wb-spaces --areas, parsed: the glob spaces an idea can go in. [] when it can't say."""
    rc, out, _ = wb_doctor.run([os.path.join(wb_doctor.REPO, "bin", "wb-spaces"), "--areas"])
    try:
        return json.loads(out) if rc == 0 else []
    except ValueError:
        return []


def check_name(name, rows, parent):
    """'' when name can be a new folder in parent and a new space's label; else why not."""
    if not name.strip():
        return "it needs a name"
    if name != name.strip():
        return "a name can't start or end with a space"
    if "/" in name:
        return "a name can't have a / in it"
    if name.startswith("."):
        return "a name can't start with ."
    if any(ord(c) < 32 or ord(c) == 127 for c in name):
        return "a name can't have a control character in it"
    for r in rows:
        for label in (r["label"], r["group"]):
            if label and label.lower() == name.lower():
                return "already a space called %s" % label
    path = os.path.join(parent, name)
    if os.path.lexists(path):
        return "%s exists; to make it a space, run wb-setup" % path
    return ""


def _git(root, *args):
    rc, out, err = wb_doctor.run(["git"] + list(args), cwd=root)
    return rc == 0, (out + err).strip()


def _add_process(root):
    with open(TEMPLATE, encoding="utf-8") as f:
        section = f.read()
    path = os.path.join(root, "CLAUDE.md")
    before = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            before = f.read()
    with open(path, "w", encoding="utf-8") as f:
        f.write(before.rstrip("\n") + "\n" + section if before else section.lstrip("\n"))
    ok, out = _git(root, "add", "CLAUDE.md")
    if ok:
        ok, out = _git(root, "commit", "-q", "-m", "workbench: how work is done here")
    return ok, out


def _left(root, done, failed):
    q = shlex.quote(root)
    prefix = bead_prefix(os.path.basename(root))
    finish = {
        "git": "cd %s && git init -b main && bd init --prefix %s" % (q, prefix),
        "backlog": "cd %s && bd init --prefix %s" % (q, prefix),
        "process": "append %s to %s/CLAUDE.md and commit it" % (TEMPLATE, q),
        "config": "add it to %s by hand (spaces.example.toml shows how)" % tilde(wb_doctor.config_path()),
    }.get(failed)
    parts = ["made %s (%s)" % (root, ", ".join(done))] if done else []
    if finish:
        parts.append("to finish: " + finish)
    if done:
        parts.append("or to remove it: rm -rf %s" % q)
    return "; ".join(parts)


def create(kind, name, area=None, account=None):
    """Make a new space. Never prompts; stops at the first failed step. Returns a dict:
    ok, root, space, kind, worktrees, done (step names), left (what's there and how to finish or
    remove it), error."""
    res = {"ok": False, "root": "", "space": name, "kind": kind, "worktrees": False,
           "done": [], "left": "", "error": ""}
    if kind not in KINDS:
        res["error"] = "kind must be one of %s" % ", ".join(KINDS)
        return res
    if os.path.exists(wb_doctor.config_path()):
        rows, err, _ = wb_doctor.spaces()
        if rows is None:
            res["error"] = "spaces.toml doesn't read: %s" % err
            return res
    else:
        rows = []  # the first space: append_spaces makes the file
    a = None
    if area is not None:
        if kind != "idea":
            res["error"] = "only an idea goes in an area; a tool is its own space"
            return res
        a = next((x for x in areas() if x["name"] == area), None)
        if a is None:
            res["error"] = "no area called %s" % area
            return res
    parent = a["parent"] if a else default_parent()
    why = check_name(name, rows, parent)
    if not why and a and a["worktrees"] and name in {r["space_key"] for r in rows if r["worktrees"]}:
        # the folder's name becomes its key, and wb-spaces refuses a config where two share one
        why = "%s is already a space's key; pick another name" % name
    if why:
        res["error"] = why
        return res
    root = os.path.join(parent, name)
    worktrees = a["worktrees"] if a else kind == "tool"
    res.update(root=root, worktrees=worktrees)

    def fail(step, why):
        res["error"] = why
        res["left"] = _left(root, res["done"], step)
        return res

    try:
        os.makedirs(parent, exist_ok=True)
        os.mkdir(root)
    except OSError as e:
        return fail("folder", "couldn't make %s: %s" % (root, e))
    res["done"].append("folder")
    ok, out = _git(root, "init", "-q", "-b", "main")
    if not ok:
        return fail("git", "git init failed: %s" % out)
    res["done"].append("git")
    ok, out = init_backlog(root, ["--prefix", bead_prefix(name)])
    if not ok:
        return fail("backlog", "bd init failed: %s" % out.strip())
    res["done"].append("backlog")
    if worktrees:
        ok, out = _add_process(root)
        if not ok:
            return fail("process", "couldn't commit the CLAUDE.md process section: %s" % out)
        res["done"].append("process")
    if a is None:
        space = {"name": name, "root": root, "beads": "true", "worktrees": worktrees}
        if worktrees:
            space["space_key"] = unique_key(name, {r["space_key"] for r in rows if r["worktrees"]})
        if account:
            space["claude_config"] = os.path.abspath(os.path.expanduser(account))
        ok, err = append_spaces(wb_doctor.config_path(), [space],
                                os.path.join(wb_doctor.REPO, "spaces.example.toml"))
        if not ok:
            return fail("config", "the new space didn't read back from spaces.toml (%s); it is as it was" % err)
        res["done"].append("config")
    elif wb_doctor.spaces()[0] is None:
        # nothing was written, but an area's new folder is a new row: make sure the config still reads
        return fail("config", "the spaces don't read with %s in %s: %s" % (name, a["name"], wb_doctor.spaces()[1]))
    res["ok"] = True
    return res
