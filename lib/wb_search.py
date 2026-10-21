"""The work screen's search, shared by wb-ui (which beads match, and the list's
highlights) and wb-backlog (the preview's highlights), so a highlight always
shows why a bead matched.

A word of 1-2 letters matches only whole or as a plural ("po": "PO", "POs"),
because as a prefix it matches half the backlog ("policy", "portal", "post").
A longer word matches from the start of a word ("fab": "fabric", "fabrics").
Case is ignored.
"""
import re

HL, END = "\033[1;33m", "\033[0m"


def patterns(query):
    # "PO's" is "po", not "po" and "s": a lone "s" would match every possessive
    words = dict.fromkeys(w.split("'")[0] for w in re.findall(r"\w[\w']*", query.lower()))
    return [re.compile(r"\b" + re.escape(w) + (r"(?:e?s)?\b" if len(w) <= 2 else r"\w*"), re.I)
            for w in words]


def hits(pats, text):
    return sum(bool(p.search(text)) for p in pats)


def highlight(pats, text):
    if not pats:
        return text
    return re.compile("|".join(p.pattern for p in pats), re.I).sub(lambda m: HL + m.group(0) + END, text)
