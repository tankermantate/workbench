"""wb_judge_bd — the only bd the grooming judge may run.

A prefix rule like `Bash(bd --readonly list:*)` lets anything follow the subcommand, and bd's
global flags go anywhere: `--profile` writes files into the space's tree, `--db`, `-C` and
`--global` read another store, `--readonly=false` undoes the point. So the judge's one Bash rule
names a per-run script (wb-groom writes it into the run dir, where the judge can't write) that
calls main() below with the space root, bd's absolute path and a fixed environment baked in:
nothing the judge can put in front of the call (cd, VAR=…, PATH) reaches bd. main() checks the
arguments against a whitelist and execs `bd --readonly --sandbox <sub> …` in the root, no shell.
"""
import os
import re
import sys

ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")  # a bead id; never an option
NUM_RE = re.compile(r"^[0-9]{1,6}$")
MAX_IDS = 50


class Refused(Exception):
    pass


def _flags(args, allowed, numeric=()):
    """ARGS split into flags (each in ALLOWED, or in NUMERIC followed by a number) and the rest,
    which must be bead ids. Raises Refused."""
    flags, ids, i = [], [], 0
    while i < len(args):
        a = args[i]
        if a in allowed:
            flags.append(a)
        elif a in numeric:
            if i + 1 >= len(args) or not NUM_RE.match(args[i + 1]):
                raise Refused(f"{a} needs a number")
            flags += [a, args[i + 1]]
            i += 1
        elif ID_RE.match(a):
            ids.append(a)
        else:
            raise Refused(f"{a!r} is not allowed")
        i += 1
    return flags, ids


def check(args):
    """The bd argv after `bd --readonly --sandbox` for the judge's ARGS. Raises Refused."""
    args = list(args)
    if args[:2] == ["dep", "tree"]:
        sub, rest, ids_wanted = ["dep", "tree"], args[2:], (1, 1)
        allowed, numeric = {"--json"}, ()
    elif args[:1] == ["list"]:
        sub, rest, ids_wanted = ["list"], args[1:], (0, 0)
        allowed, numeric = {"--json", "--all"}, ("-n",)
    elif args[:1] == ["ready"]:
        sub, rest, ids_wanted = ["ready"], args[1:], (0, 0)
        allowed, numeric = {"--json"}, ("-n",)
    elif args[:1] == ["show"]:
        sub, rest, ids_wanted = ["show"], args[1:], (1, MAX_IDS)
        allowed, numeric = {"--json"}, ()
    elif args[:1] == ["children"]:
        sub, rest, ids_wanted = ["children"], args[1:], (1, 1)
        allowed, numeric = {"--json"}, ()
    else:
        raise Refused("only list, show, ready, dep tree and children")
    flags, ids = _flags(rest, allowed, numeric)
    lo, hi = ids_wanted
    if not lo <= len(ids) <= hi:
        raise Refused(f"{' '.join(sub)} takes {lo if lo == hi else f'{lo} to {hi}'} bead id(s)")
    return sub + ids + flags


def main(args, root, bd, env):
    try:
        sub = check(args)
    except Refused as e:
        print(f"wb-judge-bd: refused: {e}. Allowed: list [-n N] [--all] [--json]; show ID… [--json]; "
              "ready [-n N] [--json]; dep tree ID [--json]; children ID [--json]", file=sys.stderr)
        return 2
    os.chdir(root)
    os.execve(bd, [bd, "--readonly", "--sandbox", *sub], env)
