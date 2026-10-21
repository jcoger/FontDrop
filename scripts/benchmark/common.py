"""Shared helpers for the web-pairs benchmark. Python 3 stdlib only."""
import json, os, re

WORK = os.environ.get("FD_BENCH_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".bench"))
GF_META = os.environ.get("FD_GF_META", os.path.join(WORK, "gf", "gf-metadata.json"))
CACHE = os.path.join(WORK, "bench-cache")
FONTS = os.path.join(WORK, "bench-fonts")
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "docs", "research", "benchmarks")

SKIP_RE = re.compile(r"icons?\b|symbols?\b|emoji|^noto\b|^material\b", re.I)


def load_meta():
    s = open(GF_META, encoding="utf-8").read()
    d = json.loads(s[s.index("{"):])
    return sorted(d["familyMetadataList"], key=lambda x: (x["popularity"], x["family"]))


def eligible(m):
    """Not an icon/emoji/Noto family."""
    return not (m.get("isNoto") or SKIP_RE.search(m["family"]))


def top_families(n=150):
    return [m["family"] for m in load_meta() if eligible(m)][:n]


GENERIC_FIRST = {"libre", "new", "old", "the", "bad", "big", "red", "baloo"}
TRAIL = {"sans", "serif", "slab", "mono", "condensed", "display", "text", "narrow",
         "rounded", "script", "semi", "flex", "soft", "sc", "pro", "ui", "std"}


def base_name(f):
    toks = [t for t in re.split(r"\s+", f.lower()) if t]
    while len(toks) > 1 and (toks[-1] in TRAIL or toks[-1].isdigit()):
        toks.pop()
    return " ".join(toks)


def same_superfamily(a, b):
    if a == b:
        return True
    if base_name(a) == base_name(b):
        return True
    fa, fb = a.lower().split()[0], b.lower().split()[0]
    if fa == fb and fa not in GENERIC_FIRST:
        return True
    return False
