# Provenance of raw inputs

Everything in this folder is a work of the U.S. Government prepared by EPA staff
as part of their official duties, and is therefore not subject to domestic
copyright (17 U.S.C. 105). It is reproduced here unmodified.

Indicator page (the canonical source, January 19 2025 snapshot):
<https://19january2025snapshot.epa.gov/climate-indicators/climate-change-indicators-heat-related-deaths>

Technical documentation (PDF, not vendored here):
<https://19january2025snapshot.epa.gov/system/files/documents/2024-06/heat-deaths_documentation.pdf>

## Files

| File | sha256 | Origin |
|---|---|---|
| `heat-deaths_fig-1.csv` | `727556e6…b6f67` | EPA figure 1 data download |
| `heat-deaths_fig-2.csv` | `fd16a4f7…d13eb` | EPA figure 2 data download |
| `heat-deaths_example.csv` | `543fe8bd…fc580` | EPA example figure data download |
| `epa-figure-1.png` | `29a1f6c1…16c07` | `word/media/image1.png` from the text doc |
| `epa-figure-2.png` | `bc5909b5…55b1e` | `word/media/image2.png` |
| `epa-figure-example.png` | `b50275cd…0e04c` | `word/media/image3.png` |

The three CSVs are verified byte-identical to EPA's own downloads:

- <https://19january2025snapshot.epa.gov/system/files/other-files/2024-06/heat-deaths_fig-1.csv>
- <https://19january2025snapshot.epa.gov/system/files/other-files/2024-06/heat-deaths_fig-2.csv>
- <https://19january2025snapshot.epa.gov/sites/default/files/2016-08/heat-deaths_example.csv>

The three PNGs are EPA's own rendered charts, lifted out of the text document.
They are kept as visual ground truth so our charts can be checked against what
EPA actually published. They are not used by the site.

## Source documents for the prose

`R/gen_narrative.R` extracts the indicator's prose from
`heat-deaths_text_07-08-24.docx` and writes `narrative.qmd`. Both this file and
`heat-deaths_TD_06-02-24 CLEAN.docx` (the technical documentation, currently
linked but not extracted from, see `indicator.technical_documentation` in
`data/meta.yml`) are vendored here, scrubbed of reviewer-identifying metadata:

| File | sha256 (original) | sha256 (vendored, scrubbed) |
|---|---|---|
| `heat-deaths_text_07-08-24.docx` | `de1d5857…41d71` | `df89c583…626b4` |
| `heat-deaths_TD_06-02-24 CLEAN.docx` | `76b1003a…8e5ed` | `f00aa464…3bcbb` |

The original `heat-deaths_text_07-08-24.docx` carried tracked changes,
`word/comments.xml`, and `word/people.xml`, all attributing edits to a named EPA
contract reviewer; `docProps/core.xml` on both files carried a named
`lastModifiedBy`. Committing any of that as-is would publish reviewer names and
internal editorial comments that are not part of the published page, in this
public repository.

`R/scrub_docx.R` removes it: the `w:del` markup (deleted text and its
`w:author`/`w:date`, entirely), the `w:ins` wrapper around inserted text
(unwrapped, so the inserted text itself is kept as an accepted change),
`word/comments.xml` and its associated parts, and `docProps/core.xml`'s
`lastModifiedBy`. It does not touch any visible paragraph text: verified by
running `R/utils/read_docx.R`'s reader against both the original and the
scrubbed file and confirming byte-identical output. See the script's own header
comment for the full list of what it removes.

```sh
Rscript R/scrub_docx.R <in.docx> <out.docx>
```

The checksums above identify the exact revisions used. No local filesystem path
is recorded anywhere in this repository; the vendored, scrubbed files here are
the only copies `R/gen_narrative.R` reads.

## CSV format notes (these bite)

All three CSVs are **windows-1252 encoded, not UTF-8**. The degree sign in
`heat-deaths_example.csv` is a raw `0xB0`, and the en dash in
`heat-deaths_fig-2.csv`'s title line is a raw `0x96`. Read them with an explicit
`windows-1252` locale or every non-ASCII character becomes mojibake.

Layout is identical across all three: metadata on lines 1 to 5, a blank line 6,
the header on line 7, data from line 8. So `skip = 6`.

Line 1 titles are inconsistent between files, and this is EPA's inconsistency,
not a transcription error: figure 1 uses an ASCII hyphen in `1979-2022` while
figure 2 uses an en dash in `1999–2022`.

## Updating the data

Replace the CSV(s) in this folder and rerun `R/build_data.R`. Nothing else needs
to change and no manual editing is involved. The build reads the header row to
identify series rather than relying on column position, so added years flow
through automatically; a renamed or reordered column stops the build with a clear
error instead of silently mismatching a series. Update the table above with the
new sha256 and note the new EPA "Web update" date.

## Updating the narrative

Run the replacement docx through `R/scrub_docx.R` before it goes anywhere
near this folder or `git add`, record both the original and the scrubbed sha256
above, then rerun `R/gen_narrative.R`. `narrative.qmd` is generated; a wording
problem is fixed in the generator, not by hand-editing the output.
