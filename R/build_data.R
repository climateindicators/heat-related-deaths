# Build tidy long-format data for the Heat-Related Deaths indicator.
#
#   Rscript R/build_data.R
#
# Reads the three EPA figure CSVs in data-raw/ and writes data/*.csv plus
# data/meta.yml. Rerunning with unchanged inputs produces byte-identical
# output. Nothing here touches the network.
#
# TO UPDATE THE DATA: drop replacement CSVs into data-raw/ and rerun. Series are
# matched by header string, so added years flow through untouched; a renamed or
# reordered column stops the build rather than silently swapping two series.
#
# TO ADAPT THIS FOR ANOTHER INDICATOR: the lookup tables immediately below are
# the only indicator-specific content. Everything else is mechanical.

suppressPackageStartupMessages({
  library(dplyr)
})

root <- here::here()
source(file.path(root, "R/utils/epa_csv.R"))
source(file.path(root, "R/utils/write_stable.R"))

raw_dir <- file.path(root, "data-raw")
out_dir <- file.path(root, "data")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Indicator constants -----------------------------------------------------

# Deaths through 1998 are coded under ICD-9, 1999 onward under ICD-10. EPA marks
# this only as a visual gap in Figure 1 plus a footnote; carrying it as a data
# column is what lets the chart split the line without a hand-placed break, and
# what lets a downstream user see the discontinuity at all.
ICD10_FIRST_YEAR <- 1999L

# Non-ASCII characters are constructed rather than typed, so this source file
# stays pure ASCII. R on Windows reads a script in the native encoding unless
# told otherwise, which would turn a literal degree sign into mojibake and break
# the header match against the (windows-1252) source CSV.
DEGREE_SIGN <- intToUtf8(0x00B0)
EN_DASH     <- intToUtf8(0x2013)

INDICATOR <- list(
  name                    = "Heat-Related Deaths",
  slug                    = "heat-related-deaths",
  publisher               = "U.S. Environmental Protection Agency",
  source_page             = "https://19january2025snapshot.epa.gov/climate-indicators/climate-change-indicators-heat-related-deaths",
  technical_documentation = "https://19january2025snapshot.epa.gov/system/files/documents/2024-06/heat-deaths_documentation.pdf",
  rights                  = "Public domain, work of the U.S. Government (17 U.S.C. 105)"
)

# ---- Series lookup tables ----------------------------------------------------
#
# `source_header` must match the CSV header byte for byte. `label` is the
# display string; where it differs from the source header it is taken from the
# legend of EPA's own published chart (see data-raw/epa-figure-*.png), not
# invented here.

FIG1_SERIES <- tibble::tribble(
  ~source_header,                                                   ~series_key,                          ~label,
  "Underlying cause of death (all year)",                           "underlying_all_year",                "Underlying cause of death (all year)",
  "Underlying and contributing causes of death (May-Sept)",         "underlying_or_contributing_may_sep", "Underlying and contributing causes of death (May-Sept)"
)

# Order here is EPA's chart legend order (descending magnitude), which is NOT
# the order the columns appear in the source file and NOT the order the caption
# prose names the colours. Nothing in this repo may reach a series by column
# position.
FIG2_SERIES <- tibble::tribble(
  ~source_header,                                                       ~series_key,     ~label,
  "Crude summer death rate per million, age 65+ population",            "age_65_plus",   "Age 65+",
  "Crude summer death rate per million, non-Hispanic black population", "nh_black",      "Non-Hispanic Black people",
  "Crude summer death rate per million, general population",            "general",       "General population"
)

EXAMPLE_SERIES <- tibble::tribble(
  ~source_header,                    ~series_key,            ~label,                            ~unit,
  "Daily deaths, 1995",              "deaths_1995",          "Daily deaths, 1995",              "deaths",
  "Average daily deaths, 1990-2000", "deaths_avg_1990_2000", "Average daily deaths, 1990-2000", "deaths",
  paste0("Daily high temperature, 1995 (", DEGREE_SIGN, "F)"),
                                     "high_temp_f",          "Daily high temperature, 1995",    "degrees Fahrenheit"
)

# ---- Helpers -----------------------------------------------------------------

# Drop blank cells and attach the series lookup. Blank source cells are OMITTED
# rather than written as empty values: in Figure 1 the blanks are years for
# which that method's series does not exist, and an empty `value` invites a
# reader to treat it as a zero. meta.yml records each series' real coverage.
#
# A populated cell always becomes a row, even when it holds a suppression
# marker rather than a number: "Suppressed" is information. Such rows carry an
# empty `value` and `flag = "suppressed"`.
tidy_series <- function(df, id_cols, lookup) {
  out <- df |>
    tidyr::pivot_longer(
      cols      = -dplyr::all_of(id_cols),
      names_to  = "source_header",
      values_to = "raw_value"
    ) |>
    dplyr::filter(!is.na(raw_value), trimws(raw_value) != "") |>
    dplyr::inner_join(lookup, by = "source_header")

  split <- split_value_flag(out$raw_value)
  out$value <- split$value
  out$flag  <- split$flag
  out
}

coverage_of <- function(long, key) {
  yrs <- long$year[long$series_key == key]
  sprintf("%d%s%d", min(yrs), EN_DASH, max(yrs)) # en dash, as an escape for the reason above
}

# ---- Figure 1: annual heat-related death rates -------------------------------

f1_path <- file.path(raw_dir, "heat-deaths_fig-1.csv")
f1_meta <- read_epa_preamble(f1_path)
f1_raw  <- read_epa_csv(f1_path)
assert_headers(f1_raw, "Year", FIG1_SERIES$source_header, "heat-deaths_fig-1.csv")

f1 <- tidy_series(f1_raw, "Year", FIG1_SERIES) |>
  dplyr::mutate(
    year         = as.integer(Year),
    icd_revision = dplyr::if_else(year < ICD10_FIRST_YEAR, "ICD-9", "ICD-10"),
    measure      = "death_rate",
    unit         = "deaths per million people"
  ) |>
  dplyr::arrange(year, match(series_key, FIG1_SERIES$series_key)) |>
  dplyr::select(year, series_key, series_label = label, icd_revision, measure, unit, value, flag)

assert_conservation(f1_raw, FIG1_SERIES$source_header, nrow(f1), "figure 1")

# ---- Figure 2: summer heat + cardiovascular disease death rates --------------

f2_path <- file.path(raw_dir, "heat-deaths_fig-2.csv")
f2_meta <- read_epa_preamble(f2_path)
f2_raw  <- read_epa_csv(f2_path)
assert_headers(f2_raw, "Year", FIG2_SERIES$source_header, "heat-deaths_fig-2.csv")

f2 <- tidy_series(f2_raw, "Year", FIG2_SERIES) |>
  dplyr::mutate(
    year    = as.integer(Year),
    measure = "crude_summer_death_rate",
    unit    = "deaths per million people"
  ) |>
  dplyr::arrange(year, match(series_key, FIG2_SERIES$series_key)) |>
  dplyr::select(year, population_key = series_key, population_label = label, measure, unit, value, flag)

assert_conservation(f2_raw, FIG2_SERIES$source_header, nrow(f2), "figure 2")

# Backstop against a series mix-up. The primary defence is that series are keyed
# by header string, but this indicator is unusually exposed to a swap because the
# caption names the colours in a different order than the file lists the columns,
# so it is worth a second, data-driven check.
#
# The only ordering that actually holds is that 65+ is the highest of the three
# in every year. Non-Hispanic Black is NOT uniformly above the general
# population: it falls below in 2017, 2020 and 2022. Do not "restore" that
# assertion, it is false.
f2_check <- f2 |>
  dplyr::mutate(v = suppressWarnings(as.numeric(value))) |>
  tidyr::pivot_wider(id_cols = year, names_from = population_key, values_from = v)
stopifnot(
  "figure 2: the 65+ series should be the highest of the three in every year" =
    all(f2_check$age_65_plus >= pmax(f2_check$nh_black, f2_check$general, na.rm = TRUE))
)

# Suppression is expected only in the non-Hispanic Black series, which is the
# smallest population and therefore the one that trips CDC's disclosure
# threshold. Report rather than assert: a future update could legitimately
# suppress elsewhere.
f2_flagged <- dplyr::filter(f2, flag != "")
if (nrow(f2_flagged)) {
  cat("\nSuppressed cells in figure 2 (plotted as gaps, not zeros):\n")
  for (i in seq_len(nrow(f2_flagged))) {
    cat(sprintf("  %d  %s  [%s]\n", f2_flagged$year[i],
                f2_flagged$population_label[i], f2_flagged$flag[i]))
  }
}

# ---- Example figure: 1995 Chicago heat wave ----------------------------------

ex_path <- file.path(raw_dir, "heat-deaths_example.csv")
ex_meta <- read_epa_preamble(ex_path)
ex_raw  <- read_epa_csv(ex_path)
assert_headers(ex_raw, c("Month", "Day", "Year"), EXAMPLE_SERIES$source_header, "heat-deaths_example.csv")

ex <- tidy_series(ex_raw, c("Month", "Day", "Year"), EXAMPLE_SERIES) |>
  dplyr::mutate(
    # Build the ISO string directly rather than formatting a Date object, so
    # neither the session locale nor readr's date formatting can reach the file.
    date = sprintf("%04d-%02d-%02d", as.integer(Year), as.integer(Month), as.integer(Day))
  ) |>
  dplyr::arrange(date, match(series_key, EXAMPLE_SERIES$series_key)) |>
  dplyr::select(date, measure_key = series_key, measure_label = label, unit, value, flag)

stopifnot("example figure dates are not all valid" = !anyNA(as.Date(ex$date)))
assert_conservation(ex_raw, EXAMPLE_SERIES$source_header, nrow(ex), "example figure")

# ---- Write ------------------------------------------------------------------

write_csv_stable(f1, file.path(out_dir, "heat_deaths_annual.csv"))
write_csv_stable(f2, file.path(out_dir, "heat_deaths_summer_cvd.csv"))
write_csv_stable(ex, file.path(out_dir, "chicago_1995_heat_wave.csv"))

# ---- Data dictionary ---------------------------------------------------------

col <- function(name, type, description) {
  list(name = name, type = type, description = description)
}

meta <- list(
  indicator = INDICATOR,
  datasets = list(
    list(
      file            = "heat_deaths_annual.csv",
      figure          = "Figure 1",
      figure_title    = f1_meta$title,
      source_file     = "heat-deaths_fig-1.csv",
      source_sha256   = file_sha256(f1_path),
      source_encoding = "windows-1252",
      data_source     = f1_meta$data_source,
      web_update      = f1_meta$web_update,
      unit            = f1_meta$units,
      rows            = nrow(f1),
      columns = list(
        col("year", "integer", "Calendar year"),
        col("series_key", "string", "Machine-readable series identifier"),
        col("series_label", "string", "Display label, as used in EPA's published chart legend"),
        col("icd_revision", "string", paste0(
          "ICD revision in force for that year: ICD-9 through ",
          ICD10_FIRST_YEAR - 1L, ", ICD-10 from ", ICD10_FIRST_YEAR,
          ". Added by this build; not a column in EPA's file."
        )),
        col("measure", "string", "What is measured"),
        col("unit", "string", "Unit of `value`"),
        col("value", "number", "Death rate, verbatim from the source file. Empty when `flag` is set."),
        col("flag", "string", paste(
          "Empty for an ordinary observation. `suppressed` means the source",
          "withheld the value because the underlying count fell below CDC's",
          "disclosure threshold. A suppressed value is not zero and not missing",
          "at random, and is drawn as a gap rather than plotted."
        ))
      ),
      series = list(
        list(
          key           = "underlying_all_year",
          label         = FIG1_SERIES$label[FIG1_SERIES$series_key == "underlying_all_year"],
          source_header = FIG1_SERIES$source_header[FIG1_SERIES$series_key == "underlying_all_year"],
          coverage      = coverage_of(f1, "underlying_all_year"),
          note          = paste(
            "Deaths for which excessive natural heat was the underlying cause.",
            "Values before and after the ICD-9 to ICD-10 change are not directly",
            "comparable, which is why EPA draws this line with a break."
          )
        ),
        list(
          key           = "underlying_or_contributing_may_sep",
          label         = FIG1_SERIES$label[FIG1_SERIES$series_key == "underlying_or_contributing_may_sep"],
          source_header = FIG1_SERIES$source_header[FIG1_SERIES$series_key == "underlying_or_contributing_may_sep"],
          coverage      = coverage_of(f1, "underlying_or_contributing_may_sep"),
          note          = paste(
            "Deaths for which heat was the underlying or a contributing cause,",
            "May to September only. Blank in the source file outside the coverage",
            "range above; those year/series combinations are omitted from this",
            "file rather than written as empty values, because the series does",
            "not exist for those years."
          )
        )
      )
    ),
    list(
      file            = "heat_deaths_summer_cvd.csv",
      figure          = "Figure 2",
      figure_title    = f2_meta$title,
      source_file     = "heat-deaths_fig-2.csv",
      source_sha256   = file_sha256(f2_path),
      source_encoding = "windows-1252",
      data_source     = f2_meta$data_source,
      web_update      = f2_meta$web_update,
      unit            = f2_meta$units,
      rows            = nrow(f2),
      columns = list(
        col("year", "integer", "Calendar year"),
        col("population_key", "string", "Machine-readable population group identifier"),
        col("population_label", "string", "Display label, as used in EPA's published chart legend"),
        col("measure", "string", "What is measured"),
        col("unit", "string", "Unit of `value`"),
        col("value", "number", "Death rate, verbatim from the source file. Empty when `flag` is set."),
        col("flag", "string", paste(
          "Empty for an ordinary observation. `suppressed` means the source",
          "withheld the value because the underlying count fell below CDC's",
          "disclosure threshold. A suppressed value is not zero and not missing",
          "at random, and is drawn as a gap rather than plotted."
        ))
      ),
      series = lapply(seq_len(nrow(FIG2_SERIES)), function(i) {
        list(
          key           = FIG2_SERIES$series_key[i],
          label         = FIG2_SERIES$label[i],
          source_header = FIG2_SERIES$source_header[i],
          coverage      = coverage_of(dplyr::rename(f2, series_key = population_key), FIG2_SERIES$series_key[i])
        )
      }),
      note = paste(
        "Restricted to summer (May to September) deaths with cardiovascular",
        "disease as the underlying cause and heat as a contributing cause.",
        "The source file lists columns as general, 65+, non-Hispanic Black;",
        "this build keys every series by header string, never by position."
      )
    ),
    list(
      file            = "chicago_1995_heat_wave.csv",
      figure          = "Example figure",
      figure_title    = ex_meta$title,
      source_file     = "heat-deaths_example.csv",
      source_sha256   = file_sha256(ex_path),
      source_encoding = "windows-1252",
      data_source     = ex_meta$data_source,
      web_update      = ex_meta$web_update,
      unit            = ex_meta$units,
      rows            = nrow(ex),
      columns = list(
        col("date", "date", "Calendar date, ISO 8601"),
        col("measure_key", "string", "Machine-readable measure identifier"),
        col("measure_label", "string", "Display label"),
        col("unit", "string", "Unit of `value`; this file mixes deaths and degrees Fahrenheit"),
        col("value", "number", "Value, verbatim from the source file. Empty when `flag` is set."),
        col("flag", "string", "Empty for an ordinary observation; a disclosure marker otherwise.")
      ),
      series = lapply(seq_len(nrow(EXAMPLE_SERIES)), function(i) {
        list(
          key           = EXAMPLE_SERIES$series_key[i],
          label         = EXAMPLE_SERIES$label[i],
          source_header = EXAMPLE_SERIES$source_header[i],
          unit          = EXAMPLE_SERIES$unit[i]
        )
      }),
      note = paste(
        "Chicago Standard Metropolitan Statistical Area, 1 June to 31 August 1995.",
        "Source columns Month/Day/Year are combined into a single ISO date.",
        "Unlike the other two files this one mixes units, so `unit` varies by row."
      )
    )
  )
)

write_yaml_stable(meta, file.path(out_dir, "meta.yml"))

# ---- Verify what was written -------------------------------------------------

written <- file.path(out_dir, c(
  "heat_deaths_annual.csv", "heat_deaths_summer_cvd.csv",
  "chicago_1995_heat_wave.csv", "meta.yml"
))
invisible(lapply(written, assert_clean_output))

cat("\nWrote:\n")
for (p in written) {
  cat(sprintf("  %-30s %6d bytes  %s\n", basename(p), file.size(p), substr(file_sha256(p), 1, 12)))
}
cat(sprintf(
  "\nRows: figure 1 = %d, figure 2 = %d, example = %d\n", nrow(f1), nrow(f2), nrow(ex)
))
cat(sprintf(
  "Coverage: %s %s | %s %s\n",
  "underlying", coverage_of(f1, "underlying_all_year"),
  "contributing", coverage_of(f1, "underlying_or_contributing_may_sep")
))
