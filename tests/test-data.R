# Regression checks on the generated data files.
#
#   Rscript tests/test-data.R
#
# These are value snapshots, deliberately separate from R/build_data.R. The
# build asserts structural invariants that survive a data update (header match,
# conservation, series ordering); this file pins the actual numbers, so after an
# update it tells you exactly what changed instead of silently accepting it.
#
# When the data is legitimately updated, expect failures here and update the
# expectations after checking each one against the new source file.

setwd(here::here())
source("R/utils/write_stable.R")

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

f1 <- rd("heat_deaths_annual.csv")
f2 <- rd("heat_deaths_summer_cvd.csv")
ex <- rd("chicago_1995_heat_wave.csv")

val <- function(df, ...) {
  conds <- list(...)
  keep <- rep(TRUE, nrow(df))
  for (nm in names(conds)) keep <- keep & df[[nm]] == conds[[nm]]
  df$value[keep]
}

cat("\nFigure 1 (heat_deaths_annual.csv)\n")
check("67 rows", nrow(f1) == 67L)
check("columns as documented",
      identical(names(f1), c("year", "series_key", "series_label",
                             "icd_revision", "measure", "unit", "value", "flag")))
check("1979 underlying = 0.24038954",
      identical(val(f1, year = "1979", series_key = "underlying_all_year"), "0.24038954"))
check("2022 underlying = 2.93140257",
      identical(val(f1, year = "2022", series_key = "underlying_all_year"), "2.93140257"))
check("2021 contributing = 4.820819989",
      identical(val(f1, year = "2021", series_key = "underlying_or_contributing_may_sep"), "4.820819989"))
check("no 2022 contributing row",
      length(val(f1, year = "2022", series_key = "underlying_or_contributing_may_sep")) == 0L)
check("no 1998 contributing row",
      length(val(f1, year = "1998", series_key = "underlying_or_contributing_may_sep")) == 0L)
check("1998 is ICD-9",
      identical(unique(f1$icd_revision[f1$year == "1998"]), "ICD-9"))
check("1999 is ICD-10",
      identical(unique(f1$icd_revision[f1$year == "1999"]), "ICD-10"))
check("underlying series covers 1979-2022 with no gaps",
      identical(sort(as.integer(f1$year[f1$series_key == "underlying_all_year"])), 1979:2022))
check("no flags set", all(f1$flag == ""))

cat("\nFigure 2 (heat_deaths_summer_cvd.csv)\n")
check("72 rows", nrow(f2) == 72L)
check("columns as documented",
      identical(names(f2), c("year", "population_key", "population_label",
                             "measure", "unit", "value", "flag")))
check("1999 general = 1.082281458",
      identical(val(f2, year = "1999", population_key = "general"), "1.082281458"))
check("1999 age 65+ = 5.977382332",
      identical(val(f2, year = "1999", population_key = "age_65_plus"), "5.977382332"))
check("1999 non-Hispanic Black = 3.139198754",
      identical(val(f2, year = "1999", population_key = "nh_black"), "3.139198754"))
check("2022 general = 0.741101775",
      identical(val(f2, year = "2022", population_key = "general"), "0.741101775"))
check("exactly 2 suppressed cells", sum(f2$flag == "suppressed") == 2L)
check("suppressed cells are 2004 and 2014, non-Hispanic Black",
      identical(f2$year[f2$flag == "suppressed"], c("2004", "2014")) &&
        all(f2$population_key[f2$flag == "suppressed"] == "nh_black"))
check("suppressed cells carry no value, and are NOT zero",
      all(f2$value[f2$flag == "suppressed"] == ""))
# EPA's published figure draws these two points at zero. Ours must not.
check("no zero values anywhere in figure 2",
      !any(suppressWarnings(as.numeric(f2$value[f2$value != ""])) == 0))
check("all three series present in every year",
      all(table(f2$year) == 3L))

cat("\nExample figure (chicago_1995_heat_wave.csv)\n")
check("276 rows", nrow(ex) == 276L)
check("columns as documented",
      identical(names(ex), c("date", "measure_key", "measure_label",
                             "unit", "value", "flag")))
check("92 distinct dates", length(unique(ex$date)) == 92L)
check("spans 1995-06-01 to 1995-08-31",
      min(ex$date) == "1995-06-01" && max(ex$date) == "1995-08-31")
check("1995-06-01 deaths = 164",
      identical(val(ex, date = "1995-06-01", measure_key = "deaths_1995"), "164"))
check("1995-06-01 high temp = 80.06",
      identical(val(ex, date = "1995-06-01", measure_key = "high_temp_f"), "80.06"))
check("peak deaths 499 on 1995-07-15", {
  d <- ex[ex$measure_key == "deaths_1995", ]
  d$v <- as.numeric(d$value)
  max(d$v) == 499 && d$date[which.max(d$v)] == "1995-07-15"
})
check("peak temperature 104 on 1995-07-13", {
  t <- ex[ex$measure_key == "high_temp_f", ]
  t$v <- as.numeric(t$value)
  max(t$v) == 104 && t$date[which.max(t$v)] == "1995-07-13"
})
check("temperature rows carry Fahrenheit units",
      all(ex$unit[ex$measure_key == "high_temp_f"] == "degrees Fahrenheit"))
check("no flags set", all(ex$flag == ""))

cat("\nFile hygiene\n")
for (f in list.files("data", full.names = TRUE)) {
  check(sprintf("%s is UTF-8, LF, no BOM, no mojibake", basename(f)),
        tryCatch({ assert_clean_output(f); TRUE }, error = function(e) { cat("      ", conditionMessage(e), "\n"); FALSE }))
}

meta <- yaml::read_yaml("data/meta.yml")
check("meta.yml documents all three datasets", length(meta$datasets) == 3L)
check("meta.yml has no timestamp",
      !any(grepl("\\d{4}-\\d{2}-\\d{2}T|Sys\\.time|generated_at",
                 readLines("data/meta.yml", warn = FALSE))))
for (ds in meta$datasets) {
  cols <- vapply(ds$columns, function(x) x$name, character(1))
  actual <- names(rd(ds$file))
  check(sprintf("meta.yml dictionary matches %s columns", ds$file),
        identical(cols, actual))
  check(sprintf("meta.yml row count matches %s", ds$file),
        ds$rows == nrow(rd(ds$file)))
}

cat("\n")
if (length(failures)) {
  cat(sprintf("%d FAILED:\n", length(failures)))
  for (f in failures) cat("  -", f, "\n")
  quit(status = 1L)
}
cat("All data checks passed.\n")
