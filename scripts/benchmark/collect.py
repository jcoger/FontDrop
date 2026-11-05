#!/usr/bin/env python3
"""Step 2: GitHub code search for Google Fonts embed URLs, one query per family
and URL form. Raw results are cached (resumable). Needs the `gh` CLI, logged in.
Usage: collect.py [--families 150] [--sleep 7]"""
import argparse, hashlib, json, os, subprocess, sys, time
from common import CACHE, top_families

FORMS = [
    "fonts.googleapis.com/css2?family={f}&family=",
    "fonts.googleapis.com/css?family={f}|",
]


def search(q, retries=6):
    for i in range(retries):
        r = subprocess.run(["gh", "search", "code", q, "--limit", "100", "--json",
                            "repository,path,textMatches"], capture_output=True, text=True)
        if r.returncode == 0:
            return json.loads(r.stdout or "[]")
        err = (r.stderr or "").lower()
        if any(k in err for k in ("rate limit", "403", "429", "secondary", "abuse")):
            wait = 65 * (i + 1)
            print(f"  rate limited, sleeping {wait}s", file=sys.stderr, flush=True)
            time.sleep(wait)
            continue
        print("  gh error:", r.stderr[:200], file=sys.stderr, flush=True)
        time.sleep(10)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--families", type=int, default=150)
    ap.add_argument("--sleep", type=float, default=7)
    a = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    fams = top_families(a.families)
    done = ran = 0
    for f in fams:
        for form in FORMS:
            q = form.format(f=f.replace(" ", "+"))
            p = os.path.join(CACHE, hashlib.md5(q.encode()).hexdigest() + ".json")
            if os.path.exists(p):
                done += 1
                continue
            res = search(q)
            ran += 1
            if res is not None:
                json.dump({"query": q, "family": f, "results": res}, open(p, "w"))
            print(f"[{ran}] {q} -> {None if res is None else len(res)}", flush=True)
            time.sleep(a.sleep)
    print(f"done. cached={done} ran={ran}")


if __name__ == "__main__":
    main()
