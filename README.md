# heat-related-deaths

Data and narrative for the U.S. EPA climate indicator **Heat-Related Deaths**.

This repository holds EPA's raw source files, the pipeline that turns them into
analysis-ready data, and EPA's own published prose extracted from the source
Word document. It produces two things:

- `data/` — tidy long-format CSVs plus `meta.yml`, a machine-readable data
  dictionary
- `narrative.qmd` — EPA's indicator text, figure captions, and references

Both are read over the network by the website repository,
[climateindicators.us](https://github.com/climateindicators/climateindicators.us),
which is where the figures for this indicator are drawn. **No chart code lives
here.**

Part of the [climateindicators.us](https://climateindicators.us) project, which
rebuilds the EPA *Climate Change Indicators* preserved in the
[January 19, 2025 snapshot](https://19january2025snapshot.epa.gov/climate-indicators/view-indicators/index.html).

Original page:
<https://19january2025snapshot.epa.gov/climate-indicators/climate-change-indicators-heat-related-deaths>

## Rebuilding

R is not assumed to be on `PATH`.

```sh
"C:\Program Files\R\R-4.5.3\bin\Rscript.exe" R/build_data.R      # data-raw/*.csv -> data/*.csv + data/meta.yml
"C:\Program Files\R\R-4.5.3\bin\Rscript.exe" R/gen_narrative.R   # data-raw/*.docx -> narrative.qmd
"C:\Program Files\R\R-4.5.3\bin\Rscript.exe" tests/test-data.R   # data-quality checks
```

Nothing touches the network, and rerunning with unchanged inputs produces
byte-identical output.

## Layout

| Path | What it is |
|---|---|
| `data-raw/` | EPA's published CSVs and the vendored, scrubbed source Word documents, plus `PROVENANCE.md` |
| `data/` | Generated tidy long-format CSVs and `meta.yml`; committed |
| `R/utils/` | `epa_csv.R`, `read_docx.R`, `write_stable.R`; indicator-agnostic, shared across indicator repositories |
| `R/build_data.R` | The only indicator-specific data code: three series lookup tables |
| `R/gen_narrative.R` | Extracts `narrative.qmd` from the source docx |
| `narrative.qmd` | EPA's published text, figure captions, and references; generated, not hand-edited |
| `tests/` | Structural invariants plus value snapshots |

## Two departures from EPA's published figures

Both follow from representing the data honestly rather than from a stylistic
preference.

**Suppressed values are drawn as gaps, not zeros.** CDC writes `Suppressed`
where a death count falls below its disclosure threshold. This occurs twice in
Figure 2, in the non-Hispanic Black series (2004 and 2014). EPA's published
chart plots both at zero, which reads as though nobody died; the truth is that
the number is too small to publish. Here those observations carry
`flag = suppressed` and an empty value, and the line breaks.

**The ICD-9 to ICD-10 change is a data column.** Rates before and after 1999 are
not directly comparable. EPA records this as a visual gap and a footnote; here it
is `icd_revision`, so the discontinuity is visible to anything reading the file
and a chart cannot interpolate across it.

## Rights

EPA's text and data are works of the U.S. Government and are not subject to
domestic copyright (17 U.S.C. 105). See `NOTICE.md`. The code in this repository
is CC-BY-SA. This is an independent rebuild, not affiliated with or endorsed by
EPA.
