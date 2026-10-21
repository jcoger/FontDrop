#!/usr/bin/env python3
"""Step 6: download Regular/Italic/Bold/BoldItalic static TTFs for every family
in web-pairs.csv from Google Fonts (old user agent => TrueType). Fonts are saved
under FD_BENCH_DIR/bench-fonts/<Family>/ and never installed or executed.
Only fonts.gstatic.com URLs are fetched; files must start with a TrueType header."""
import csv, json, os, re, subprocess, sys, time, urllib.parse
from common import FONTS, OUT, WORK, load_meta

UA = "Mozilla/4.0"
STYLES = {("400", "normal"): "Regular", ("400", "italic"): "Italic",
          ("700", "normal"): "Bold", ("700", "italic"): "BoldItalic"}


def get(url, binary=False):
    # curl avoids the macOS python.org certificate-store problem
    r = subprocess.run(["curl", "-sSfL", "--max-time", "30", "-A", UA, url], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"curl {r.returncode}: {r.stderr.decode()[:100]}")
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def want_tokens(m):
    have = set(m["fonts"].keys())  # e.g. "400", "400i", "700i"
    return [(w, i) for w, i in (("400", ""), ("400", "i"), ("700", ""), ("700", "i")) if w + i in have]


def css_url(fam, toks):
    f = urllib.parse.quote_plus(fam)
    spec = []
    for w, i in toks:
        spec.append(w + ("italic" if i else ""))
    return f"https://fonts.googleapis.com/css?family={f}:{','.join(spec)}"


def parse_css(css):
    out = {}
    for blk in re.findall(r"@font-face\s*\{[^}]*\}", css):
        st = re.search(r"font-style:\s*(\w+)", blk)
        wt = re.search(r"font-weight:\s*(\d+)", blk)
        u = re.search(r"url\((https://fonts\.gstatic\.com/[^)]+)\)", blk)
        if st and wt and u:
            out[(wt.group(1), st.group(1))] = u.group(1)
    return out


def fetch_family(fam, m):
    toks = want_tokens(m)
    if ("400", "") not in toks:
        return None, "no 400 regular in metadata"
    css = get(css_url(fam, toks))
    faces = parse_css(css)
    saved = []
    d = os.path.join(FONTS, fam)
    os.makedirs(d, exist_ok=True)
    for key, style in STYLES.items():
        if key not in faces:
            continue
        data = get(faces[key], binary=True)
        if data[:4] not in (b"\x00\x01\x00\x00", b"true", b"OTTO"):
            continue
        path = os.path.join(d, f"{fam.replace(' ', '')}-{style}.ttf")
        open(path, "wb").write(data)
        saved.append(style)
        time.sleep(0.2)
    if "Regular" not in saved:
        return None, "no Regular TTF served"
    return saved, None


def main():
    meta = {m["family"]: m for m in load_meta()}
    fams = sorted({x for r in csv.DictReader(open(os.path.join(OUT, "web-pairs.csv"))) for x in (r["a"], r["b"])})
    ok, failed = {}, {}
    for fam in fams:
        try:
            saved, err = fetch_family(fam, meta[fam])
        except Exception as e:  # skip family cleanly, record why
            saved, err = None, f"{type(e).__name__}: {e}"
        if saved:
            ok[fam] = saved
        else:
            failed[fam] = err
        print(fam, "OK " + ",".join(saved) if saved else "FAIL " + str(err), flush=True)
        time.sleep(0.3)
    json.dump({"ok": ok, "failed": failed}, open(os.path.join(WORK, "bench-fonts-report.json"), "w"), indent=1)
    print(f"downloaded={len(ok)} failed={len(failed)}")


if __name__ == "__main__":
    main()
