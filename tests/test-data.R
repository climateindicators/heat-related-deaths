# Regression checks on the generated data for the Heat-Related Deaths indicator.
#
#   Rscript tests/test-data.R
#
# The checks below are shape-independent: they hold whatever the reshape in
# R/build_data.R turns each figure into. Value snapshots, at the bottom, pin
# the actual numbers so a data update fails loudly instead of passing silently.

setwd(here::here())
source("R/utils/write_stable.R")

# Keeps the dictionary check readable when a meta.yml field is absent altogether.
`%||%` <- function(a, b) if (is.null(a)) b else a

failures <- character()
check <- function(label, ok) {
  ok <- isTRUE(ok)
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", label))
  if (!ok) failures <<- c(failures, label)
  invisible(ok)
}

rd <- function(f) {
  readr::read_csv(file.path("data", f),
                  col_types = readr::cols(.default = readr::col_character()),
                  na = character(), progress = FALSE)
}

meta <- yaml::read_yaml("data/meta.yml")

cat("\nData dictionary\n")
check("meta.yml documents 3 dataset(s)", length(meta$datasets) == 3L)
check("meta.yml has no timestamp",
      !any(grepl("\\d{4}-\\d{2}-\\d{2}T|Sys\\.time|generated_at",
                 readLines("data/meta.yml", warn = FALSE))))

for (ds in meta$datasets) {
  df   <- rd(ds$file)
  cols <- vapply(ds$columns, function(x) x$name, character(1))
  check(sprintf("%s: meta.yml lists the columns the file actually has", ds$file),
        identical(cols, names(df)))
  check(sprintf("%s: meta.yml row count matches the file", ds$file),
        identical(as.integer(ds$rows), nrow(df)))
  check(sprintf("%s: every column has a type and a description", ds$file),
        all(vapply(ds$columns, function(x) nzchar(x$type %||% "") && nzchar(x$description %||% ""), logical(1))))
  check(sprintf("%s: source file is still present and unchanged", ds$file),
        identical(file_sha256(file.path("data-raw", ds$source_file)), ds$source_sha256))
  check(sprintf("%s: no blank rows", ds$file), nrow(df) > 0L)
}

cat("\nFile hygiene\n")
for (f in list.files("data", pattern = "[.](csv|yml)$", full.names = TRUE)) {
  check(sprintf("%s is UTF-8, LF, no BOM, no mojibake", basename(f)),
        tryCatch({ assert_clean_output(f); TRUE },
                 error = function(e) { cat("      ", conditionMessage(e), "\n"); FALSE }))
}

cat("\nValue snapshots\n")

annual <- rd("heat_deaths_annual.csv")
check("heat_deaths_annual.csv: 67 rows", nrow(annual) == 67L)
check("heat_deaths_annual.csv: first row is 1979 underlying (ICD-9)",
      identical(annual$year[1], "1979") &&
      identical(annual$series_key[1], "underlying_all_year") &&
      identical(annual$value[1], "0.24038954"))
check("heat_deaths_annual.csv: last row is 2022 underlying (ICD-10)",
      identical(annual$year[nrow(annual)], "2022") &&
      identical(annual$series_key[nrow(annual)], "underlying_all_year") &&
      identical(annual$value[nrow(annual)], "2.93140257"))
check("heat_deaths_annual.csv: value min/max",
      identical(annual$value[which.min(as.numeric(annual$value))], "0.24038954") &&
      identical(annual$value[which.max(as.numeric(annual$value))], "4.820819989"))

cvd <- rd("heat_deaths_summer_cvd.csv")
check("heat_deaths_summer_cvd.csv: 72 rows", nrow(cvd) == 72L)
check("heat_deaths_summer_cvd.csv: first row is 1999 age_65_plus",
      identical(cvd$year[1], "1999") &&
      identical(cvd$population_key[1], "age_65_plus") &&
      identical(cvd$value[1], "5.977382332"))
check("heat_deaths_summer_cvd.csv: last row is 2022 general",
      identical(cvd$year[nrow(cvd)], "2022") &&
      identical(cvd$population_key[nrow(cvd)], "general") &&
      identical(cvd$value[nrow(cvd)], "0.741101775"))
check("heat_deaths_summer_cvd.csv: value min/max",
      identical(cvd$value[which.min(as.numeric(cvd$value))], "0.078550491") &&
      identical(cvd$value[which.max(as.numeric(cvd$value))], "5.977382332"))

chicago <- rd("chicago_1995_heat_wave.csv")
check("chicago_1995_heat_wave.csv: 276 rows", nrow(chicago) == 276L)
check("chicago_1995_heat_wave.csv: first row is 1995-06-01 deaths_1995",
      identical(chicago$date[1], "1995-06-01") &&
      identical(chicago$measure_key[1], "deaths_1995") &&
      identical(chicago$value[1], "164"))
check("chicago_1995_heat_wave.csv: last row is 1995-08-31 high_temp_f",
      identical(chicago$date[nrow(chicago)], "1995-08-31") &&
      identical(chicago$measure_key[nrow(chicago)], "high_temp_f") &&
      identical(chicago$value[nrow(chicago)], "87.08"))
check("chicago_1995_heat_wave.csv: value min/max",
      identical(chicago$value[which.min(as.numeric(chicago$value))], "57.92") &&
      identical(chicago$value[which.max(as.numeric(chicago$value))], "499"))

cat("\n")
if (length(failures)) {
  cat(sprintf("%d FAILED:\n", length(failures)))
  for (f in failures) cat("  -", f, "\n")
  quit(status = 1L)
}
cat("All data checks passed.\n")
