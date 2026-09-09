# Provenance

Every file in this directory is reproduced unmodified from EPA's published
indicator page and its per-figure data downloads. To update the data, replace the
file and rerun `Rscript R/build_data.R`.

## Indicator page

- `source-page.html`  \
  <https://19january2025snapshot.epa.gov/climate-indicators/climate-change-indicators-heat-related-deaths/index.html>  \
  sha256 `2ffcbc274d4206b2731218fbfbf35ab796264cb4b08ad129fc5949fcedef72ee`

Technical documentation: <https://19january2025snapshot.epa.gov/system/files/documents/2024-06/heat-deaths_documentation.pdf>

## Figure data

- `heat-deaths_fig-1.csv`  \
  <https://19january2025snapshot.epa.gov/system/files/other-files/2024-06/heat-deaths_fig-1.csv>  \
  sha256 `727556e60b70f1cf47bdd22af938c6ccaac85f0cfb4d89ed10f9024cbeab6f67`  \
  encoding UTF-8, 44 data rows, columns: `Year`, `Underlying cause of death (all year)`, `Underlying and contributing causes of death (May-Sept)`  \
  title: Figure 1. Deaths Classified as "Heat-Related" in the United States, 1979-2022  \
  data source: CDC, 2024; web update: June 2024; units: death rate (per million people)

- `heat-deaths_fig-2.csv`  \
  <https://19january2025snapshot.epa.gov/system/files/other-files/2024-06/heat-deaths_fig-2.csv>  \
  sha256 `fd16a4f7f54ba965390dd97d7678e500bccae6acd53135158f0e2f5f2cbd13eb`  \
  encoding windows-1252, 24 data rows, columns: `Year`, `Crude summer death rate per million, general population`, `Crude summer death rate per million, age 65+ population`, `Crude summer death rate per million, non-Hispanic black population`  \
  title: Figure 2. Summer Deaths Due to Heat and Cardiovascular Disease in the United States, 1999–2022  \
  data source: CDC, 2024; web update: June 2024; units: death rate (per million people)

- `heat-deaths_example.csv`  \
  <https://19january2025snapshot.epa.gov/sites/default/files/2016-08/heat-deaths_example.csv>  \
  sha256 `543fe8bdd1e2796952b8185650138e1f3936cfd2332c8f8ed817e89c7d1fc580`  \
  encoding windows-1252, 92 data rows, columns: `Month`, `Day`, `Year`, `Daily deaths, 1995`, `Average daily deaths, 1990-2000`, `Daily high temperature, 1995 (°F)`  \
  title: Example: Examining Heat-Related Deaths During the 1995 Chicago Heat Wave  \
  data source: CDC, 2012; NOAA, 2012; web update: May 2014; units: deaths; °F

## Figures that are not on EPA's published indicator page

EPA labels the following as an example rather than a numbered figure. Say so
plainly in `README.md`, in `CLAUDE.md`, and in that figure's `meta.yml` entry.

- caption 3: Example: Examining Heat-Related Deaths During the 1995 Chicago Heat Wave*
