"""Which space a folder belongs to, and whether it's a linked worktree. Shared by the status
line segment (bin/wb-statusline-space) and the tabs view (bin/wb-tabs)."""
import functools
import os
import subprocess

WB_SPACES = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "bin", "wb-spaces")


def git_dirs(path):
    """(git dir, common dir, top level) for a checkout, or None outside git. The first two
    differ only in a linked worktree, and the common dir's parent is then the main checkout."""
    try:
        out = subprocess.run(["git", "-C", path, "--no-optional-locks", "rev-parse", "--path-format=absolute",
                              "--git-dir", "--git-common-dir", "--show-toplevel"],
                             capture_output=True, text=True, timeout=2).stdout.split("\n")
    except (OSError, subprocess.SubprocessError):
        return None
    return (out[0], out[1], out[2] if len(out) > 2 else "") if len(out) > 1 and out[0] and out[1] else None


def rows():
    """wb-spaces' rows, split into fields; [] when it can't say."""
    try:
        out = subprocess.run([WB_SPACES], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return []
    return [] if out.returncode else [line.split("\t") for line in out.stdout.splitlines()]


def roots(space_rows=None):
    # (root, label, worktree space's key or None)
    return [(os.path.realpath(r[2]), r[0], r[6] if r[4] == "1" else None)
            for r in (rows() if space_rows is None else space_rows) if len(r) > 6]


@functools.lru_cache(maxsize=None)  # one space's root is asked about once per tab in wb-tabs
def toplevel(path):
    try:
        out = subprocess.run(["git", "-C", path, "--no-optional-locks", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    return os.path.realpath(out) if out else None


def worktree_owner(folder, main, spaces):
    """end-session's rule: a worktree space whose root is in the same repo, preferring the
    one whose key names the worktree (new-session makes <key>-<slug>)."""
    on_repo = [(label, key) for root, label, key in spaces if key and toplevel(root) == main]
    name = os.path.basename(folder)
    return next((label for label, key in on_repo if name.startswith(key + "-")),
                on_repo[0][0] if on_repo else None)


def owner(path, spaces):
    """The label of the space whose root holds path; the deepest root wins."""
    best = None
    for root, label, _ in spaces:
        if (path == root or path.startswith(root.rstrip("/") + "/")) and (not best or len(root) > len(best[0])):
            best = (root, label)
    return best[1] if best else None


def locate(folder, spaces=None):
    """(label, is a space, worktree folder or None) for a folder."""
    folder = os.path.realpath(folder)
    dirs = git_dirs(folder)
    worktree = (os.path.realpath(dirs[2]) if dirs[2] else folder) if dirs and dirs[0] != dirs[1] else None
    spaces = roots() if spaces is None else spaces
    label = owner(folder, spaces)
    if not label and worktree:
        # a worktree lives outside its space's root; its main checkout doesn't
        main = os.path.realpath(os.path.dirname(dirs[1]))
        label = worktree_owner(worktree, main, spaces) or owner(main, spaces)
    return (label, True, worktree) if label else (os.path.basename(folder), False, worktree)
