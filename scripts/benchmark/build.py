#!/usr/bin/env python3
"""Steps 2b-5: parse cached search results, build positives, negatives and book
pairs, write web-pairs.csv and a stats JSON. Fixed seed 42. Stdlib only."""
import csv, glob, json, os, random, re, sys
from collections import defaultdict
from urllib.parse import unquote_plus
from common import CACHE, OUT, WORK, load_meta, eligible, same_superfamily

SEED = 42
MIN_REPOS = 3
CAP_FRAC = 0.05
URL_RE = re.compile(r"fonts\.googleapis\.com/css2?\?[^\s\"'<>)\\]+")


def parse_url(u, canon):
    """Return sorted tuple of exactly 2 distinct canonical family names, or None."""
    u = u.replace("&amp;", "&").replace("\\u0026", "&").replace("%7C", "|").replace("%7c", "|")
    q = u.split("?", 1)[1]
    if any(c in q for c in "${}") or "%7B" in q.upper():
        return None
    fams = []
    for part in q.split("&"):
        if part.startswith("family="):
            for v in part[7:].split("|"):
                name = unquote_plus(v.split(":")[0]).strip()
                if name:
                    fams.append(name)
    fams = [canon.get(f.lower(), f) for f in fams]
    if len(set(fams)) != 2 or len(fams) > 4:
        return None
    # exactly 2 distinct families (same family repeated for several axes is fine)
    return tuple(sorted(set(fams)))


def main():
    meta = load_meta()
    canon = {m["family"].lower(): m["family"] for m in meta}
    pop = {m["family"]: m["popularity"] for m in meta}
    stats = {"queries": 0, "files": 0, "urls_parsed": 0, "urls_two_family": 0}
    repos = defaultdict(lambda: defaultdict(set))  # pair -> repo -> {urls}
    for p in sorted(glob.glob(os.path.join(CACHE, "*.json"))):
        d = json.load(open(p))
        stats["queries"] += 1
        for r in d["results"]:
            stats["files"] += 1
            repo = r["repository"]
            if repo.get("isFork") or repo.get("isPrivate"):
                continue
            name = repo["nameWithOwner"].lower()
            for m in r.get("textMatches", []):
                for u in URL_RE.findall(m["fragment"]):
                    stats["urls_parsed"] += 1
                    pr = parse_url(u, canon)
                    if pr:
                        stats["urls_two_family"] += 1
                        repos[pr][name].add(repo["url"])
    # observed pairs (any count) -> used to keep negatives clean
    observed = defaultdict(set)
    for (a, b) in repos:
        observed[a].add(b); observed[b].add(a)

    cand = {}
    for (a, b), rs in repos.items():
        if a not in pop or b not in pop or len(rs) < MIN_REPOS:
            continue
        if same_superfamily(a, b):
            continue
        cand[(a, b)] = rs
    stats["candidates_pre_cap"] = len(cand)

    # family cap: no family in more than 5% of kept pairs
    kept = dict(cand)
    def _count(k):
        c = defaultdict(int)
        for a, b in k:
            c[a] += 1; c[b] += 1
        return c
    dropped = []
    while True:
        c = _count(kept)
        cap = max(1, int(CAP_FRAC * len(kept)))
        over = [f for f, n in c.items() if n > cap]
        if not over:
            break
        f = max(over, key=lambda x: (c[x], x))
        # drop f's lowest-count pair; tie -> partner with most pairs, then name
        ps = [k for k in kept if f in k]
        ps.sort(key=lambda k: (len(kept[k]), -c[k[0] if k[1] == f else k[1]], k))
        d = ps[0]
        dropped.append((d, len(kept[d])))
        del kept[d]
    stats["after_cap"] = len(kept)
    stats["cap_per_family"] = max(1, int(CAP_FRAC * len(kept)))
    stats["cap_dropped"] = len(dropped)
    stats["cap_dropped_examples"] = [[list(d), n] for d, n in dropped[:15]]

    rows = []
    positives = sorted(kept)
    for (a, b) in positives:
        rs = kept[(a, b)]
        ex = []
        for n in sorted(rs):
            ex.append(sorted(rs[n])[0])
        rows.append([a, b, 1, "github", len(rs), ";".join(ex[:3])])

    # books
    books = json.load(open(os.path.join(OUT, "books-pairs.json")))
    bpos = bneg = bneu = 0
    book_rows = []
    for r in books:
        ag, bg = r.get("a_google"), r.get("b_google")
        if not (ag and bg):
            continue
        ag, bg = canon.get(ag.lower(), ag), canon.get(bg.lower(), bg)
        if ag not in pop or bg not in pop:
            continue
        v = r["verdict"]
        if v == "praised":
            lab = 1; bpos += 1
        elif v == "criticised":
            lab = 0; bneg += 1
        else:
            bneu += 1; continue
        book_rows.append([ag, bg, lab, "books", "", ""])
    stats.update(books_positive=bpos, books_negative=bneg, books_neutral_skipped=bneu)

    # negatives: one per github positive (A,B) -> (A,C)
    rng = random.Random(SEED)
    ranked = [m["family"] for m in meta]  # sorted by popularity
    decile = {f: min(9, i * 10 // len(ranked)) for i, f in enumerate(ranked)}
    pool = defaultdict(list)
    for m in meta:
        if eligible(m):
            pool[decile[m["family"]]].append(m["family"])
    pos_partner = defaultdict(set)
    for (a, b) in positives:
        pos_partner[a].add(b); pos_partner[b].add(a)
    for r in book_rows:
        if r[2] == 1:
            pos_partner[r[0]].add(r[1]); pos_partner[r[1]].add(r[0])
    neg_rows = []
    seen_neg = set()
    for (a, b) in positives:
        cands = [c for c in sorted(pool[decile[b]])
                 if c != a and not same_superfamily(a, c)
                 and c not in pos_partner[a] and c not in observed[a]
                 and (a, c) not in seen_neg]
        if not cands:
            continue
        c = rng.choice(cands)
        seen_neg.add((a, c))
        neg_rows.append([a, c, 0, "negative", "", ""])
    stats["negatives"] = len(neg_rows)

    out = os.path.join(OUT, "web-pairs.csv")
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["a", "b", "label", "source", "repo_count", "example_repos"])
        w.writerows(rows + neg_rows + book_rows)
    fams = sorted({x for r in rows + neg_rows + book_rows for x in r[:2]})
    json.dump(fams, open(os.path.join(WORK, "bench-families.json"), "w"), indent=1)
    stats["families_total"] = len(fams)
    stats["github_positives"] = len(rows)
    top = sorted(rows, key=lambda r: -r[4])[:10]
    stats["top10"] = [[r[0], r[1], r[4]] for r in top]
    json.dump(stats, open(os.path.join(WORK, "bench-stats.json"), "w"), indent=1)
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
