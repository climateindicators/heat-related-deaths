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

The three CSVs were copied from the local archive at
`…/archive/Excel Files - Indicator Workbooks (for published indicator updates as of 7-23-2026)/Heat-related deaths/`
and verified byte-identical to their source. They are also downloadable from EPA:

- <https://19january2025snapshot.epa.gov/system/files/other-files/2024-06/heat-deaths_fig-1.csv>
- <https://19january2025snapshot.epa.gov/system/files/other-files/2024-06/heat-deaths_fig-2.csv>
- <https://19january2025snapshot.epa.gov/sites/default/files/2016-08/heat-deaths_example.csv>

The three PNGs are EPA's own rendered charts, lifted out of the text document.
They are kept as visual ground truth so our charts can be checked against what
EPA actually published. They are not used by the site.

## Source documents deliberately NOT vendored

The indicator prose was extracted once from these two Word files, which live in
the archive and are **not** copied into this repository:

| File | sha256 |
|---|---|
| `heat-deaths_text_07-08-24.docx` | `de1d5857…41d71` |
| `heat-deaths_TD_06-02-24 CLEAN.docx` | `76b1003a…8e5ed` |

Two reasons they stay out. First, the prose now lives in `index.qmd`, which is
the artifact the site renders and the thing to edit; keeping a second copy of the
same words in a binary format invites the two to disagree. Second, both files
carry tracked changes, `word/comments.xml`, and `word/people.xml`, so committing
them would publish EPA reviewers' names and internal editorial comments, which
are not part of the published page.

`R/gen_narrative.R` can regenerate the prose from the archive for anyone who has
it. The checksums above identify the exact revisions used.

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
