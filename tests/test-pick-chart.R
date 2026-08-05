# Tests for the mechanical chart selector.
#
#   Rscript tests/test-pick-chart.R
#
# Builds the three tidy frames straight from data-raw/ rather than reading
# data/, so the selector can be exercised without depending on the state of
# R/build_data.R. Synthetic cases at the end cover the rules the heat indicator
# happens not to exercise.

# Run from the repository root.
stopifnot("run this from the repository root" = dir.exists("R/utils"))

source("R/utils/epa_csv.R")
source("R/utils/pick_chart.R")

pass <- 0L; fail <- 0L
check <- function(what, ok) {
  if (isTRUE(ok)) {
    pass <<- pass + 1L; cat("  ok   ", what, "\n")
  } else {
    fail <<- fail + 1L; cat("  FAIL ", what, "\n")
  }
}

# ---- fixture builders (stand-ins for R/build_data.R output) ------------------

long_from <- function(path, id_cols, lookup, extra = NULL) {
  raw <- read_epa_csv(path)
  out <- list()
  for (i in seq_len(nrow(lookup))) {
    h <- lookup$source_header[i]
    sv <- split_value_flag(raw[[h]])
    keep <- !(sv$value == "" & sv$flag == "")
    out[[i]] <- data.frame(
      id           = raw[[id_cols]][keep],
      series_key   = lookup$series_key[i],
      series_label = lookup$label[i],
      unit         = if (!is.null(lookup$unit)) lookup$unit[i] else "deaths per million people",
      value        = sv$value[keep],
      flag         = sv$flag[keep],
      stringsAsFactors = FALSE
    )
  }
  df <- do.call(rbind, out)
  names(df)[1] <- id_cols
  df
}

FIG1 <- data.frame(
  source_header = c("Underlying cause of death (all year)",
                    "Underlying and contributing causes of death (May-Sept)"),
  series_key    = c("underlying_all_year", "underlying_or_contributing_may_sep"),
  label         = c("Underlying cause of death (all year)",
                    "Underlying and contributing causes of death (May-Sept)"),
  stringsAsFactors = FALSE
)

FIG2 <- data.frame(
  source_header = c("Crude summer death rate per million, age 65+ population",
                    "Crude summer death rate per million, non-Hispanic black population",
                    "Crude summer death rate per million, general population"),
  series_key    = c("age_65_plus", "nh_black", "general"),
  label         = c("Age 65+", "Non-Hispanic Black people", "General population"),
  stringsAsFactors = FALSE
)

DEG <- intToUtf8(0x00B0)
EX <- data.frame(
  source_header = c("Daily deaths, 1995", "Average daily deaths, 1990-2000",
                    paste0("Daily high temperature, 1995 (", DEG, "F)")),
  series_key    = c("deaths_1995", "deaths_avg_1990_2000", "high_temp_f"),
  label         = c("Daily deaths, 1995", "Average daily deaths, 1990-2000",
                    "Daily high temperature, 1995"),
  unit          = c("deaths", "deaths", "degrees Fahrenheit"),
  stringsAsFactors = FALSE
)

# ---- Figure 1 ----------------------------------------------------------------

cat("\n== Figure 1: annual heat-related death rates ==\n")
f1 <- long_from("data-raw/heat-deaths_fig-1.csv", "Year", FIG1)
names(f1)[names(f1) == "Year"] <- "year"
f1$year <- as.integer(f1$year)
f1$icd_revision <- ifelse(f1$year < 1999L, "ICD-9", "ICD-10")

s1 <- pick_chart(f1)
print(s1)
check("fig1 -> line",                    s1$chart == "line")
check("fig1 -> single panel",            s1$layout == "single" && s1$n_panels == 1L)
check("fig1 x detected as year",         s1$x == "year" && s1$x_type == "year")
check("fig1 series column auto-detected", s1$series == "series_key" && s1$n_series == 2L)
check("fig1 partition = icd_revision",   identical(s1$partition, "icd_revision"))
check("fig1 underlying series is broken", "underlying_all_year" %in% s1$broken)
check("fig1 contributing series not broken",
      !("underlying_or_contributing_may_sep" %in% s1$broken))
check("fig1 -> direct labels",           s1$label_style == "direct")

# ---- Figure 2 ----------------------------------------------------------------

cat("\n== Figure 2: summer heat + cardiovascular disease ==\n")
f2 <- long_from("data-raw/heat-deaths_fig-2.csv", "Year", FIG2)
names(f2)[names(f2) == "Year"] <- "year"
f2$year <- as.integer(f2$year)

s2 <- pick_chart(f2)
print(s2)
check("fig2 -> line",                 s2$chart == "line")
check("fig2 -> single panel",         s2$n_panels == 1L)
check("fig2 3 series",                s2$n_series == 3L)
check("fig2 no partition",            is.null(s2$partition))
check("fig2 order is 65+ > black > general",
      identical(s2$series_order, c("age_65_plus", "nh_black", "general")))
check("fig2 detects suppression",     "suppressed" %in% s2$sentinels)
check("fig2 counts 2 suppressed obs", s2$n_gaps == 2L)

# ---- Example figure ----------------------------------------------------------

cat("\n== Example figure: 1995 Chicago heat wave ==\n")
ex_raw <- read_epa_csv("data-raw/heat-deaths_example.csv")
ex_raw$date <- sprintf("%04d-%02d-%02d", as.integer(ex_raw$Year),
                       as.integer(ex_raw$Month), as.integer(ex_raw$Day))
ex <- do.call(rbind, lapply(seq_len(nrow(EX)), function(i) {
  sv <- split_value_flag(ex_raw[[EX$source_header[i]]])
  keep <- !(sv$value == "" & sv$flag == "")
  data.frame(date = ex_raw$date[keep], series_key = EX$series_key[i],
             series_label = EX$label[i], unit = EX$unit[i],
             value = sv$value[keep], flag = sv$flag[keep], stringsAsFactors = FALSE)
}))

s3 <- pick_chart(ex)
print(s3)
check("example -> line",                    s3$chart == "line")
check("example x detected as date",         s3$x == "date" && s3$x_type == "date")
check("example -> SMALL MULTIPLES, not dual axis",
      s3$layout == "small_multiples")
check("example -> 2 panels",                s3$n_panels == 2L)
check("example panels are the two units",
      setequal(s3$panels, c("deaths", "degrees Fahrenheit")))
check("example is dense -> no markers",     !s3$show_points && s3$n_points_max == 92L)
check("example no partition",               is.null(s3$partition))

# ---- synthetic edge cases ----------------------------------------------------

cat("\n== synthetic edge cases ==\n")

one <- data.frame(year = 2000:2010, series_key = "a",
                  unit = "u", value = as.character(1:11), stringsAsFactors = FALSE)
s <- pick_chart(one)
check("single series -> no labelling",  s$label_style == "none" && s$n_series == 1L)

cat_x <- data.frame(x = c("North", "South", "East", "West"), series_key = "a",
                    unit = "u", value = c("3", "1", "4", "2"), stringsAsFactors = FALSE)
s <- pick_chart(cat_x)
check("categorical x -> bar",           s$chart == "bar" && s$x_type == "categorical")

many <- do.call(rbind, lapply(letters[1:9], function(k) {
  data.frame(year = 2000:2005, series_key = k, unit = "u",
             value = as.character(1:6), stringsAsFactors = FALSE)
}))
err <- tryCatch({ pick_chart(many); NULL }, error = function(e) conditionMessage(e))
check("9 series -> refuses",            !is.null(err) && grepl("Refusing", err))

six <- do.call(rbind, lapply(letters[1:6], function(k) {
  data.frame(year = 2000:2005, series_key = k, unit = "u",
             value = as.character(1:6), stringsAsFactors = FALSE)
}))
s <- pick_chart(six)
check("6 series -> legend not direct",  s$label_style == "legend")

three_u <- do.call(rbind, lapply(1:3, function(i) {
  data.frame(year = 2000:2005, series_key = paste0("s", i), unit = paste0("u", i),
             value = as.character(1:6), stringsAsFactors = FALSE)
}))
s <- pick_chart(three_u)
check("3 units -> 3 panels",            s$n_panels == 3L && s$layout == "small_multiples")

s <- pick_chart(f1, partition = NA)
check("partition suppressible",         is.null(s$partition) && length(s$broken) == 0L)

# ---- result ------------------------------------------------------------------

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0L) quit(status = 1L)
