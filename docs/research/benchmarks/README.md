# Web pairs benchmark

Real typeface pairings that people shipped, plus matched negatives. Built from public GitHub code. Follows section 4 of `docs/research/pairing-from-web.md`.

Files:
- `web-pairs.csv`: columns `a,b,label,source,repo_count,example_repos`. `source` is `github` (positive), `negative`, or `books`.
- `books-pairs.json`: the book pairs (input).

## Method
1. Take the 150 most popular Google Fonts families (lowest `popularity` in the metadata JSON). Icon, emoji, Noto and Material families are excluded.
2. For each family X, run two GitHub code searches: `fonts.googleapis.com/css2?family=X&family=` and `fonts.googleapis.com/css?family=X|`. Up to 100 hits each. 300 queries in total. Raw results are cached.
3. Parse every embed URL in the text matches. Keep URLs that load exactly 2 distinct families. Names are normalised (`+` to space, axis specs dropped, matched to the canonical Google Fonts name).
4. Count each unordered pair by distinct repository. Forks and private repos are skipped.
5. Keep pairs with 3 or more repos, both families in Google Fonts, not the same family, not a superfamily pair. Superfamily rule: same base name after dropping words like Sans, Serif, Slab, Mono, Display, or the same first word (except generic first words such as Libre). This drops Roboto/Roboto Slab, PT Sans/PT Serif, IBM Plex*, Source Serif/Source Sans, DM Sans/DM Serif.
6. Family cap: no family appears in more than 5% of kept pairs. The family with the most pairs loses its lowest-count pair first, repeated until stable.
7. Negatives: for each github positive (A,B), one negative (A,C). C is random, from the same popularity decile as B (deciles over all 1,950 families), not the same family, not a superfamily of A, not a positive partner of A, and never seen with A in any repo. Seed 42.
8. Book pairs: rows of `books-pairs.json` with both faces on Google Fonts. `praised` is label 1, `criticised` is label 0, `neutral` is skipped. `source=books`, no repo count. A few book pairs are superfamily pairs (Merriweather/Merriweather Sans, Roboto/Roboto Slab, Alegreya Sans/Alegreya, Fira Sans/Fira Mono). They are kept as given. Filter them with `same_superfamily` in `scripts/benchmark/common.py` if needed.

## Counts (built 2026-10-21)
- Searches run: 300. Files returned: 22,797.
- Embed URLs parsed: 29,333. With exactly 2 families: 16,495.
- Pairs with 3+ repos after filters: 766. After the 5% family cap: 484 (cap = 24 pairs per family). The cap removed 282 pairs.
- Positives (github): 484. Negatives: 484. Book pairs: 10 (all praised).
- Total rows: 978. Families: 342. All 342 downloaded, 0 failed.
- This is above the 100-200 target. Rebuilding with `MIN_REPOS = 5` in `build.py` gives 167 pairs after the cap (395 before). `MIN_REPOS = 6` gives 107. The CSV keeps `repo_count`, so you can also filter it, but that skips the re-cap.

## Biases
- Popularity bias. Only the top 150 families seed the search, and each pair needs a seed family as its first family. Pairs of two rare fonts are missing.
- Order bias. Search matches the first family in the URL. A pair is found only when its first-listed family is a seed, or when the second also happens to be in the snippet.
- Copy bias. Tutorials, bootcamp templates and course repos get copied. Some counts reflect one template cloned many times (Indie Flower + Lobster at 65 repos). Repos are distinct, authors are not.
- "Shipped" is not "good". A repo using a pair is weak evidence of taste. Popular fonts dominate (Roboto, Open Sans, Poppins, Montserrat).
- GitHub search returns at most 100 hits per query and is not exhaustive or stable. Re-runs give different results.
- Embed URLs say nothing about which family is the heading and which is the body. `a,b` is alphabetical, not a role.
- Negatives are "not seen together", not "known bad". Some will be fine pairs.
- Only Google Fonts families are covered.

## Rebuild
Needs Python 3, the `gh` CLI logged in, `curl`, and the Google Fonts metadata JSON at `.bench/gf/gf-metadata.json` (get it with `curl -sL https://fonts.google.com/metadata/fonts -o .bench/gf/gf-metadata.json`; junk before the first `{` is fine). Set `FD_BENCH_DIR` or `FD_GF_META` to move the work folder.

```
python3 scripts/benchmark/collect.py     # ~45 min, 300 searches, resumable, cached under $FD_BENCH_DIR/bench-cache
python3 scripts/benchmark/build.py       # writes docs/research/benchmarks/web-pairs.csv
python3 scripts/benchmark/fonts.py       # downloads TTFs to $FD_BENCH_DIR/bench-fonts/<Family>/
```

Code search is rate limited to about 10 requests a minute. `collect.py` sleeps 7 seconds between calls and backs off on 403/429.

## Licence
The repo stores only font names and public repo URLs. Fonts come from Google Fonts under OFL or Apache 2.0 and are not committed. Downloads are never installed or executed. Repo URLs point to third-party code and carry no licence grant. Use the CSV as research data.

## First results (2026-10-21)

935 of 978 rows scored (43 missing fonts). AUC = chance a real pair outscores a popularity-matched fake (0.5 = coin flip).

| Scorer | AUC |
|---|---|
| FontDrop engine before the rulebook changes (04e33d0) | 0.513 |
| + pen-made vs constructed camps | 0.511 |
| + near-duplicate / width penalties | 0.505 |
| + foundry weakened (current) | 0.511 |
| x-height closeness alone | 0.543 |
| cap-height closeness alone | 0.538 |
| same skeleton alone | 0.512 |
| same foundry alone | 0.509 |
| serif vs sans differ alone | 0.479 |
| stroke texture differs alone | 0.457 |

Reading: no rule predicts what developers ship together on the web. Shipped pairs lean slightly toward *similar* metrics (x-height, cap, texture), not contrast. Effects are small (SE about 0.02). This set measures practice, not quality: template clones (Indie Flower + Lobster, 65 repos) count as positives. Use it to check that lenses don't fight real practice, not as a target to optimise a single score.
