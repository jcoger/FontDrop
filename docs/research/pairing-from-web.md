# Font pairing: what the web says

Research date: 2026-10-21. Method: web search and page fetches. Page content was treated as data.
Items marked **UNVERIFIED** could not be confirmed from a primary page. Search was not exhaustive (no live GitHub, Kaggle or Hugging Face queries).

## 0. Short answer

- No public, licensed, large dataset of real font pairs exists that I could find. The best academic one (Adobe's) does not link a download.
- Popularity explains most "good pair" labels in real data. Any benchmark must control for it.
- For a Google-Fonts-only benchmark, the cleanest route is to mine pairs from openly licensed sources (open-source sites and open PDFs), not to scrape curated sites.
- Measured features with the best expert support: x-height, stroke contrast, serif vs sans category, width, weight. Experts disagree on whether similarity or contrast should dominate.

## 1. Academic and technical work

### Jiang et al., "Visual Font Pairing" (Adobe + Northeastern, IEEE TMM 2019)
- **Data.** "FontPairing" database. Built from more than 300,000 freely available PDFs (about 15M pages). Scanned PDFs (43%) were dropped.
- **How pairs were found.** Heuristics read the largest text box as header, the next as sub-header or the nearest body box as body. Precision was about 95% for header/body and 85% for header/sub-header on a hand-labelled subset.
- **Size.** Header/body: 2,086 unique headers, 1,443 bodies, 13,251 pairs. Header/sub-header: 8,733 pairs. After removing the 50 most popular body fonts, 5,337 and 5,174 pairs remain.
- **Why they did not use web lists.** The authors say Google Fonts, Typ.io and Typewolf lists are small and skewed. Their count: 43% of those pairs involve one of five fonts.
- **Signals.** Appearance features from DeepFont (768-d CNN features), fed to dual-space k-NN and asymmetric similarity metric learning (ASML). Pairing is asymmetric: header and body roles are not interchangeable.
- **Results worth knowing.**
  - Binary good/bad classification, full set: popularity baseline 73.6%, DS-kNN 76.9%, ASML 65.0%, designer-rule "contrast similarity" (ConSim, from Fontjoy) 55.8%.
  - Non-popular set: popularity 55.3%, ConSim 67.3%, ASML 68.2%.
  - So a popularity prior beats most rules until popular fonts are removed. Gains from appearance are modest (about 12 points over chance).
  - In their human study, designers chose the real PDF pair over a random one about 75% of the time. Non-designers chose it 60-65% of the time.
- **Access.** Paper on arXiv. I found no dataset or code link in the paper text. Related Adobe patent US11003831 covers the method. Licence of the data: none stated. Treat as not downloadable. **UNVERIFIED** whether authors share on request.
- Links: arXiv 1811.08015.

### Fontjoy (Jack Qiao, 2018, Google Experiments)
- **Idea.** Embed each font as a vector. Good pairs share some features and contrast on others. Similarity score is cosine distance split into positive and negative halves, so it rewards both likeness and difference.
- **Data.** 1,883 Google Fonts (weights counted separately). Each rendered as an image of key letters, then a pretrained feature extractor plus PCA. Vectors are in the repo (`fonts-vectors200.json`, `vectors-200.tsv`, `metadata.tsv`).
- **Licence.** MIT.
- **Limits.** No human pair labels. The author says contrast pairs do not always work, though the hit rate is high. It is a generator, not ground truth.
- **Use for FontDrop.** The vectors are a ready, MIT, Google-Fonts-only appearance embedding. Useful as a baseline to beat, and as a feature source.
- Links: fontjoy.com/pairing, github.com/Jack000/fontjoy.

### Google patent US10115215, "Pairing fonts for presentation"
- Computes about 58 numeric features per font (curviness, stroke width, serif traits, x-height, cap height). A model maps them to 16 categories (7 serif, 4 sans, 4 other). Hand-written rules say which categories pair "exceptionally" or "well". Display, blackletter, script, symbol fonts are not paired.
- Ranking uses popularity and user interaction. No labelled pair dataset is described.
- Useful as evidence that the industry baseline is category rules plus popularity.

### Other leads (citation-level only, not read)
- FontCLIP (Tatsukawa et al., Computer Graphics Forum 2024) and Impression-CLIP (Kubota et al., 2024): fonts embedded with text/impression labels. **UNVERIFIED** details and licences. Not pairing datasets.
- Google Fonts has category (METADATA.pb) and tags in its API. The google/fonts repo is open (OFL/Apache per family). No pairing field found.
- I found no Kaggle or Hugging Face font-pair dataset. Small curated sets exist (Fonttrio claims 50+ pairs, licence not stated; fontfyi package has 15 curated pairs).

## 2. Sources of real-world pairs

| Source | Size | Access | Terms | Bias |
|---|---|---|---|---|
| Fonts In Use | Large (thousands of Uses; exact total not stated) | Website, RSS. No API or export found | Terms exclude "data mining, robots, spiders" and downloading the site. Personal, non-commercial licence. **Do not scrape.** | Editorial taste, design-press era, paid and foundry fonts, many non-Google fonts |
| Google Fonts "popular pairings" (specimen pages) | One short list per family | Site only. Existed in 2018 (Jiang) and 2020 (blog). **UNVERIFIED** if still live or exposed in API. Not in METADATA.pb or the Developer API | Google Fonts site terms not checked. Check before collecting | Strong popularity bias (Jiang: 43% involve top-5 fonts) |
| Typewolf | Curated lists and lookbooks. Free Google Fonts page lists 40 fonts with example sites | Website. Terms page not retrievable (404) | **UNVERIFIED**. Read terms first | Trend bias, one editor's taste, favours popular body fonts |
| Typ.io | Was cited by Jiang. Status **UNVERIFIED** | - | - | Same web-list skew |
| Material Design "Google Fonts pairings" (Figma templates) | Small set | Open-source templates per Google | Not read in full | Google-picked, popular fonts |
| Foundry guides (Monotype/MyFonts, Typekit/Adobe) | Handfuls | Articles | Copyright text. Facts (which two fonts) are not protected, prose is | Retail bias, superfamily bias, mostly paid fonts |
| Jiang PDF method | 13k header/body pairs | Reproducible method, not data | Use only open PDFs (Wikimedia Commons) | Document-type bias (reports, academic). Less trend bias |
| Open-source websites and templates (my suggestion) | Unlimited | GitHub code search for CSS `font-family` on headings and body | Per-repo licences. Store only font-name pairs and repo URLs | Template bias, heavy Google Fonts popularity (Inter, Roboto, Playfair) |

Bias summary: curated lists reflect trend and popularity. Foundry lists reflect superfamilies and paid catalogues. Real-document mining reflects defaults (what is installed or bundled), not taste. None is neutral.

## 3. Expert heuristics

- **Start with x-height** (Typekit, "Type Study"). Then cap height, ascender/descender length, aperture and counter size, stroke contrast, terminals. Pairs should match in some of these and differ in a few deliberate ones.
- **Shared skeleton, different surface** (Monotype/MyFonts guide, Soskolne): similar underlying structure (x-height, open apertures, proportion) with contrasting style reads as cousins, not siblings.
- **Contrast with a role** (Typekit, Jiang intro): serif with sans, expressive with neutral. Give each face a job (headline vs body).
- **Not too similar** (Typekit): two close serifs look like a mistake. Examples given: Apolline and Calluna too alike. Rooney and Skolar fine.
- **Historical context** (Typekit): old-style serifs with humanist sans (pen-based forms). Avoid anachronisms.
- **Superfamily is the safe choice** (Typekit, Google Fonts Knowledge, Monotype): shared proportions and structure by design.
- **Weight and width** (Monotype): matched weight gives a coherent lockup. Width is rarely discussed.
- Google Fonts Knowledge and Butterick's Practical Typography pages could not be read (empty or 404). **UNVERIFIED** what they add.

**Where experts disagree**
1. Contrast vs similarity. Nix (Monotype) says pairing is about contrast. Soskolne says shared structure. Fontjoy and Jiang's intro say both.
2. Weight: match weights (coherent) vs huge weight shifts (also works).
3. Family vs mixed foundries: family is "reliable", mixed foundries are a deliberate choice.
4. No source gives numeric thresholds. All advice is qualitative, and the Monotype guide is a retailer's catalogue.

## 4. Recommendation

### Best two ground-truth sources for a Google-Fonts-only benchmark
1. **Mined real use, openly licensed.** Pull heading/body font pairs from open-source sites and templates on GitHub (and optionally open-licence PDFs, as Jiang did). Keep only pairs where both families are on Google Fonts. Anyone can re-run it. Store pair names plus source URLs, not content.
2. **Google Fonts' own specimen pairings, as a small cross-check.** Only if the feature is still live and its terms allow it. Collect by hand or with permission. Use as a held-out set, not for tuning.

Skip Fonts In Use scraping (terms forbid it). Treat Typewolf as reading material until terms are checked.

### Collecting about 100-200 pairs legally
1. Query GitHub for repos with permissive licences (MIT, Apache, CC0) that load Google Fonts. Parse heading and body families from the CSS.
2. Keep pairs seen in 3 or more independent repos. Drop same-family pairs. Record header/body role.
3. Down-weight popular fonts. Cap any family at 5% of pairs. Report results with and without the top 50 fonts, as Jiang did.
4. Make negatives popularity-matched: random pairs drawn with the same frequency distribution.
5. Add a designer-reviewed set of 30-40 pairs from several practitioners (not one person). Record source for each.
6. Publish the pair list as CSV with a CC0 or CC-BY licence and the scripts.

### Features with the most weight
Ranked by support in the sources above:
1. **Popularity prior.** Not a design feature but the strongest predictor. Report it as the baseline FontDrop must beat.
2. **Category contrast (serif/sans) plus role.** Used in the Google patent, Typekit, Jiang.
3. **x-height ratio and cap height.** First check named by Typekit and Monotype.
4. **Stroke contrast and aperture/skeleton.** Named by Monotype and Typekit.
5. **Weight and width.** Named, weaker evidence.
6. **Era or skeleton family.** Typekit's historical argument. This maps to FontDrop's skeleton class.
7. **Foundry and designer.** Only a proxy for superfamily and house style. No source says it predicts taste.

## What this changes for FontDrop

- Add a popularity baseline to the eval. If the engine does not beat it, the rules add nothing.
- Treat "similar on some axes, contrasting on others" as the core scoring shape (Fontjoy, Jiang, Monotype). Do not reward pure similarity or pure contrast.
- Score header and body as different roles. Pairing is asymmetric.
- Penalise near-duplicates (too similar), not only mismatches.
- Put x-height first in the similarity set. Keep skeleton as the era/structure signal.
- Treat foundry as a weak or optional signal. Exclude same-family and superfamily pairs from the benchmark so they do not inflate scores.
- Replace the 9-pair eval with a mined set of 100-200 pairs plus negatives. Report accuracy with and without popular fonts.
- Use Fontjoy's MIT vectors as a free appearance baseline.

## Links

- Jiang et al., Visual Font Pairing: https://arxiv.org/abs/1811.08015
- Patent US11003831 (asymmetric metric learning): https://patents.google.com/patent/US11003831
- Fontjoy method: https://fontjoy.com/pairing/
- Fontjoy code and vectors (MIT): https://github.com/Jack000/fontjoy
- Google patent, pairing fonts for presentation: https://patents.google.com/patent/US10115215
- Fonts In Use terms: https://fontsinuse.com/terms-and-conditions-of-use/
- Fonts In Use about page: https://fontsinuse.com/about
- Typewolf Google Fonts: https://www.typewolf.com/google-fonts
- Monotype/MyFonts pairings guide: https://www.myfonts.com/a/font/content/monotype-studio-pairings-guide
- Typekit, Type Study: Pairing typefaces: https://blog.typekit.com/2012/05/23/type-study-pairing-typefaces/
- Google Fonts Knowledge, superfamily pairing: https://fonts.google.com/knowledge/choosing_type/pairing_typefaces_within_a_family_superfamily
- Hashrocket note on Google Fonts popular pairings (2020): https://til.hashrocket.com/posts/ozlmklqh24-google-font-popular-pairings
- Google Fonts METADATA.pb guide: https://googlefonts.github.io/gf-guide/metadata.html
- Google Fonts Developer API: https://developers.google.com/fonts/docs/developer_api
- Material Design, Google Fonts pairings: https://m3.material.io/blog/google-fonts-pairing-figma
- Fonttrio pairings (licence unstated): https://mintlify.wiki/kapishdima/fonttrio/concepts/font-pairings
