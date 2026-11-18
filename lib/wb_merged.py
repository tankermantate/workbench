#!/usr/bin/env python3
"""Whether a branch's work reached the base branch through a squash-merged pull request.

A squash merge puts one new commit on the base, so the branch is never its ancestor and
`merge-base --is-ancestor` calls it unmerged forever. gh can tell: the branch is merged when a
pull request from it into the base is MERGED and that PR's head is exactly the branch's tip, so
nothing local goes beyond what merged. end-session and wb-tidy both ask here, so they agree.

  wb_merged.py REPO BRANCH BASE TIP [GH_ACCOUNT]   prints "PR #N" and exits 0 when squash-merged,
                                                   else exits 1

Fails closed: gh missing, logged out, slow (WB_GH_TIMEOUT, default 15s) or saying something
unreadable reads as not merged, which is what ancestry alone said before. WB_GH is a test seam.
"""
import json
import os
import signal
import subprocess
import sys

GH = os.environ.get("WB_GH", "gh")


def _timeout():
    try:
        return float(os.environ.get("WB_GH_TIMEOUT", "15"))
    except ValueError:
        return 15.0


def _run(cmd, cwd=None, env=None):
    """(returncode, stdout), or None when it fails to run or outlives the timeout. gh runs in its
    own process group, killed whole: a child left holding the pipe would otherwise keep us waiting."""
    try:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    except OSError:
        return None
    try:
        out, _ = p.communicate(timeout=_timeout())
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.communicate()
        return None
    return p.returncode, out


def _env(account):
    """gh's environment, signed in as the space's account when it names one. A token for this
    call only, so gh's active account (another tab may rely on it) is left alone."""
    if not account:
        return None
    r = _run([GH, "auth", "token", "--user", account])
    token = r[1].strip() if r and not r[0] else ""
    return {**os.environ, "GH_TOKEN": token} if token else None


def merged_prs(repo, base, account=None, head=None):
    """The merged PRs into base, as dicts with number/headRefName/headRefOid; None when gh can't say.
    One call per repo: head narrows it to one branch's."""
    cmd = [GH, "pr", "list", "--state", "merged", "--base", base, "--limit", "200",
           "--json", "number,headRefName,headRefOid,baseRefName"]
    if head:
        cmd += ["--head", head]
    r = _run(cmd, cwd=repo, env=_env(account))
    try:
        data = json.loads(r[1]) if r and not r[0] else None
    except ValueError:
        return None
    return data if isinstance(data, list) else None


def squash_pr(prs, branch, base, tip):
    """The number of the merged PR from branch into base whose head is tip, else None. Each field
    is checked here, not trusted to gh's filters: a PR into another branch, or one whose head is
    behind the worktree, doesn't count."""
    for pr in prs or []:
        if (isinstance(pr, dict) and pr.get("headRefName") == branch and pr.get("baseRefName") == base
                and tip and pr.get("headRefOid") == tip and isinstance(pr.get("number"), int)):
            return pr["number"]
    return None


def main(argv):
    if len(argv) not in (4, 5):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    repo, branch, base, tip = argv[:4]
    account = argv[4] if len(argv) == 5 else None
    n = squash_pr(merged_prs(repo, base, account, head=branch), branch, base, tip)
    if n is None:
        return 1
    print(f"PR #{n}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
