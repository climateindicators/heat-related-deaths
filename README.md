# heat-related-deaths

A rebuild of the U.S. EPA climate indicator **Heat-Related Deaths**, as a
Quarto website: EPA's published text and data, presented with interactive
charts and analysis-ready downloads.

Part of the [climateindicators.us](https://climateindicators.us) project, which
rebuilds the EPA *Climate Change Indicators* preserved in the
[January 19, 2025 snapshot](https://19january2025snapshot.epa.gov/climate-indicators/view-indicators/index.html).

Original page:
<https://19january2025snapshot.epa.gov/climate-indicators/climate-change-indicators-heat-related-deaths>

## Build

R is not assumed to be on `PATH`.

```sh
"C:\Program Files\R\R-4.5.3\bin\Rscript.exe" R/build_data.R    # data-raw/ -> data/
"C:\Program Files\R\R-4.5.3\bin\Rscript.exe" tests/test-data.R # verify
quarto render                                                   # -> _site/
quarto preview                                                  # dev server
```

`R/build_data.R` is deterministic: rerunning it with unchanged inputs produces
byte-identical output, so a rebuild never shows up as noise in the diff.

## Updating the data

1. Drop replacement CSVs into `data-raw/`.
2. Rerun `R/build_data.R`.
3. Rerun `tests/test-data.R`. Expect the value snapshots to fail; check each
   change against the new source file, then update the expectations.
4. `quarto render`.

No manual editing of `data/` is involved, and no step needs a language model.
Series are matched by **header string, never by column position**, so added
years flow through untouched while a renamed or reordered column stops the build
with a clear error instead of silently mismatching a series.

## Layout

| Path | What it is |
|---|---|
| `data-raw/` | EPA's published files, unmodified, plus `PROVENANCE.md` |
| `data/` | Generated tidy long-format CSVs and `meta.yml`; committed |
| `R/utils/` | `epa_csv.R`, `write_stable.R`, `pick_chart.R`; indicator-agnostic, meant for reuse |
| `R/build_data.R` | The only indicator-specific data code: three series lookup tables |
| `index.qmd` | The indicator page. EPA's text lives here, not in a Word file. |
| `data.qmd` | Downloads and the full data dictionary |
| `tests/` | Structural invariants plus value snapshots |

A page reads `data/` and nothing else. It never opens `data-raw/` and never
touches the network.

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
