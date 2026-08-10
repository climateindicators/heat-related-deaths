# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**This file is the only place project rules live.** Code comments explain the
specific line or block they sit above — why *this* header is asserted, why
*this* value is rounded — and nothing broader. If a comment would apply to more
than one file, it belongs here instead.

## Project Overview

This repository is the **data and narrative pipeline for a single EPA climate
indicator, Heat-Related Deaths**. It takes the raw source files EPA published,
in `data-raw/`, and turns them into two products:

1. `data/` — tidy long-format CSVs plus `data/meta.yml`, a machine-readable
   data dictionary
2. `narrative.qmd` — EPA's own published prose, extracted from the source Word
   document

Both are consumed by the website repository, `../climateindicators.us`
(published at [climateindicators.us](https://climateindicators.us)): `data/` is
fetched off `raw.githubusercontent.com` at render time, and the prose in
`narrative.qmd` is lifted into `indicators/heat-related-deaths.qmd` there.

**This repository is not a website and draws no figures.** All chart code lives
in the site repository, in `R/heat-related-deaths.R`. Nothing here should
produce a plot, a theme, a palette, or an htmlwidget, and nothing here should
be rendered.

Source of the indicator, and the canonical reference for any wording question:
<https://19january2025snapshot.epa.gov/climate-indicators/climate-change-indicators-heat-related-deaths>

## Common Commands

```sh
Rscript R/build_data.R      # data-raw/*.csv -> data/*.csv + data/meta.yml
Rscript R/gen_narrative.R   # data-raw/*.docx -> narrative.qmd
Rscript tests/test-data.R   # regression checks on the generated data
```

On this machine `Rscript` is not on PATH. Use the full path:
`"C:\Program Files\R\R-4.5.3\bin\Rscript.exe"`.

There is no test runner and no `testthat`: each file under `tests/` is a
standalone script run with `Rscript` from the repository root, printing
PASS/FAIL lines and exiting non-zero on failure. To run one check, edit or
comment within that script — there is no selector.

`R/build_data.R` never touches the network. Rerunning it with unchanged inputs
must produce byte-identical output.

## Architecture

### Two pipelines, both one-way

**Data.** The three EPA per-figure CSVs in `data-raw/` (`heat-deaths_fig-1.csv`,
`heat-deaths_fig-2.csv`, `heat-deaths_example.csv`, EPA's own public downloads,
not an internal ERG workbook) go through `R/build_data.R`, which reads each with
`R/utils/epa_csv.R` (five-line preamble, windows-1252) and writes three tidy
CSVs plus `data/meta.yml`:

- `heat_deaths_annual.csv` — Figure 1, two series (`underlying_all_year`,
  1979–2022; `underlying_or_contributing_may_sep`, 1999–2021), death rate per
  million people. Carries a derived `icd_revision` column (ICD-9 through 1998,
  ICD-10 from 1999) that is not in EPA's source file.
- `heat_deaths_summer_cvd.csv` — Figure 2, summer cardiovascular-disease death
  rates for three populations (`age_65_plus`, `nh_black`, `general`),
  1999–2022. Two cells are CDC-suppressed (2004 and 2014, non-Hispanic Black);
  those rows carry `flag = suppressed` and an empty `value`, never zero.
- `chicago_1995_heat_wave.csv` — the example figure, daily deaths and
  temperature during the 1995 Chicago heat wave. The only file where `unit`
  varies by row (deaths vs. degrees Fahrenheit).

All three are on EPA's published indicator page; unlike cold-related-deaths,
this indicator has no supplementary figure that exists only in the technical
documentation.

`data/meta.yml` is generated, never hand-edited. It is what the site repository
reads for figure titles, data-source lines, web-update dates, units, and column
descriptions, so a caption on the website cannot drift from the build.

**Narrative.** `data-raw/heat-deaths_text_07-08-24.docx` goes through
`R/gen_narrative.R`, which writes `narrative.qmd`.
`data-raw/heat-deaths_TD_06-02-24 CLEAN.docx` (the technical documentation) is
also vendored, for provenance, but is not read by the generator: this
indicator's technical documentation is linked, not extracted from, because
(unlike cold-related-deaths' Figure TD-1) no figure here depends on it.

**`narrative.qmd` is generated, not hand-edited** — rerunning the generator
overwrites it. A wording problem is fixed in `R/gen_narrative.R`, or it is not
a wording problem but a deliberate editorial change, which belongs on the page
in the site repository. Wording that differs from EPA's docx is a bug here.

### `R/utils/` — shared, indicator-agnostic readers

- `read_docx.R` — parses `word/document.xml` with `xml2` directly. Never
  `officer::docx_summary()`, which leaks deleted text. The published EPA page
  equals the accept-all-tracked-changes rendering of the docx, and this reader
  reproduces exactly that. Raw bytes go to `read_xml()` as a raw vector, never
  through `rawToChar()`, or every curly quote and en dash becomes mojibake.
- `write_stable.R` — byte-stable CSV/YAML/lines writers plus
  `assert_clean_output()` and `file_sha256()`.
- `epa_csv.R` — reader for EPA's public per-figure CSV downloads (five-line
  preamble, windows-1252), plus `assert_headers()`, `assert_conservation()`,
  and `split_value_flag()`. This indicator reads all three of its source files
  through this reader.

This indicator's source cites with typed superscript numbers (`^9,10^`), not
real Word endnotes (`w:endnoteReference`), so `R/gen_narrative.R` numbers
references directly from the numbered list in the docx rather than deriving
display order from endnote marker positions.

### `R/scrub_docx.R` — one-time provenance-prep tool

Not part of the regular build. The two vendored Word documents originally
carried tracked-change authorship and, in one case, `word/comments.xml` and
`word/people.xml`, all naming a real EPA contract reviewer — publishing that
in this public repository would have exposed reviewer names and internal
editorial comments that are not part of EPA's published page. This script
strips that metadata (see its own header comment for the exact list) without
touching visible paragraph text, verified by running `R/utils/read_docx.R`
against the file before and after and confirming byte-identical extracted
text. See `data-raw/PROVENANCE.md` for both the original and scrubbed sha256
of each file.

### Hard rules

- **`data-raw/` is immutable input**, except for the one-time, documented
  scrub above. Files are otherwise reproduced unmodified and hashed in
  `data-raw/PROVENANCE.md`. To update the data, replace the source file and
  rerun the build.
- **Never record a local filesystem path.** A vendored file is identified in
  `PROVENANCE.md` by its sha256 and, where EPA publishes one, its own
  `19january2025snapshot.epa.gov` URL — never by a folder on any particular
  machine. Every script resolves its inputs relative to `here::here()`.
- **Read source columns by their header cells, never by position.** A renamed or
  reordered column must stop the build rather than silently swap two series.
  Figure 2's caption names its three populations in a different order than the
  file lists the columns; `assert_headers()` plus the data-driven check in
  `R/build_data.R` (the 65+ series is the highest of the three in every year)
  both guard against a swap.
- **Never re-derive a published number outside `R/build_data.R`.** If something
  downstream needs a value `data/` does not carry, add it to the build and
  regenerate, so it is tested and reproducible.
- **Generated output must be byte-identical across reruns and machines.** No
  timestamps in generated files (provenance is the source checksum), no
  locale-dependent sorting (order rows with `match()` against an explicit level
  vector), LF endings and UTF-8 without BOM.
- **Structural invariants belong in the build; value snapshots belong in the
  tests.** `R/build_data.R` asserts what should survive a data update.
  `tests/test-data.R` pins the actual numbers, so a legitimate data update fails
  loudly there and tells you exactly what changed.
- **No em dashes in prose.** Use commas, periods, parentheses, semicolons, or
  colons.

### Tests

`tests/` holds data-quality checks and nothing else: schema, coverage,
documented invariants, value snapshots, file hygiene (UTF-8/LF/no BOM), and
agreement between `data/meta.yml` and the CSVs it documents.

## What must never appear here

Each indicator was once a standalone Quarto website. That scaffolding has been
removed: `_quarto.yml`, `css/`, `images/`, `404.qmd`, `index.qmd`, the
"Data & Downloads" page `data.qmd`, `R/figures.R`, and the chart selector
`R/utils/pick_chart.R` with its test. If you find a reference to any of those,
it is stale; the figures live in the site repository now. Do not reintroduce a
rendered page here.

## Rights

EPA text, captions, and data are U.S. Government works, not subject to domestic
copyright (17 U.S.C. 105). Code and the derived data schema are CC-BY-SA. This
is an independent project, not affiliated with or endorsed by EPA or CDC. See
`NOTICE.md` and `data-raw/PROVENANCE.md`.
