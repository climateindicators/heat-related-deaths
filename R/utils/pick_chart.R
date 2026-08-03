# Mechanical chart selection.
#
# Decides what figure a tidy long table should become by reading the shape of
# the table, not the meaning of the numbers. No model, no heuristics that need
# tuning, no human judgement per indicator: the same table always yields the
# same spec, and the spec records why.
#
# The point is reuse. Each new indicator arrives as a tidy long CSV; run
# pick_chart() on it and render whatever comes back. An indicator that genuinely
# warrants something else overrides a field explicitly, which then shows up as a
# deliberate exception rather than as undocumented bespoke chart code.
#
# The single highest-value rule here is the unit test: more than one unit means
# more than one panel. That eliminates dual axes as a category. Dual axes force
# an arbitrary rescaling constant, and that constant is where the bugs live (the
# classic one being a tooltip on the rescaled series reporting the other
# series' scale).
#
# CAVEAT, read before reusing this on a new indicator. Auto-detection of the
# partition column (detect_partition) is the one part of this file that can fail
# silently: if it does not find the column that should break a series, the line
# is drawn straight through a discontinuity and nothing complains. Detection
# returns NULL on ambiguity, which is the safe direction, but "safe" here means
# "no break", not "no chart". So callers should pass partition = explicitly and
# treat auto-detection as a convenience for exploration only. R/figures.R does.

`%||%` <- function(a, b) if (is.null(a)) b else a

# Categorical palettes stop being distinguishable past roughly eight classes.
# Above this the selector refuses rather than emitting lines nobody can tell
# apart.
CHART_MAX_SERIES <- 8L

# Above this many points per series, markers turn into noise and the stroke
# should thin.
CHART_DENSE_POINTS <- 60L

# At or below this many series, direct labels beat a legend: no colour lookup,
# survives greyscale printing.
CHART_DIRECT_LABEL_MAX <- 5L


# ---- column role detection -------------------------------------------------

# Roles are auto-detected so a caller can pass a bare data frame, but every one
# can be overridden. Detection is by name, from a fixed candidate list, so it is
# predictable rather than clever.

X_CANDIDATES      <- c("year", "date", "month", "x")
SERIES_CANDIDATES <- c("series_key", "population_key", "measure_key", "group_key", "series")

detect_column <- function(df, candidates, role) {
  hit <- candidates[candidates %in% names(df)]
  if (length(hit) == 0L) {
    return(NULL)
  }
  if (length(hit) > 1L) {
    stop(
      "Ambiguous ", role, " column: ", paste(sQuote(hit), collapse = " and "),
      " are both present. Pass ", role, " = explicitly.",
      call. = FALSE
    )
  }
  hit
}

#' Classify what an x column is, from its values.
classify_x <- function(v) {
  if (inherits(v, "Date")) {
    return("date")
  }
  chr <- trimws(as.character(v))
  chr <- chr[!is.na(chr) & chr != ""]
  if (length(chr) == 0L) {
    return("categorical")
  }

  if (all(grepl("^\\d{4}-\\d{2}-\\d{2}$", chr))) {
    return("date")
  }

  num <- suppressWarnings(as.numeric(chr))
  if (anyNA(num)) {
    return("categorical")
  }
  if (all(num == trunc(num)) && all(num >= 1500) && all(num <= 2500)) {
    return("year")
  }
  "numeric"
}

#' Find a column that splits a series into segments that must not be joined.
#'
#' A partition column is one whose value is constant over contiguous runs of x
#' within a series, and which takes more than one value in at least one series.
#' Figure 1's icd_revision is the motivating case: the line must break where the
#' classification standard changed. Detecting this from the data means nothing
#' in the chart code has to know the year 1998.
detect_partition <- function(df, x, series, value, unit) {
  reserved <- c(x, series, value, unit, "measure")
  cand <- setdiff(names(df), reserved)
  cand <- cand[!grepl("_label$", cand)]
  cand <- cand[vapply(df[cand], function(col) is.character(col) || is.factor(col), logical(1))]

  ok <- vapply(cand, function(cn) {
    vals <- as.character(df[[cn]])
    n_distinct <- length(unique(vals))
    if (n_distinct < 2L || n_distinct > 5L) {
      return(FALSE)
    }
    groups <- if (is.null(series)) list(seq_len(nrow(df))) else split(seq_len(nrow(df)), df[[series]])
    varies <- FALSE
    for (idx in groups) {
      ord <- idx[order(df[[x]][idx])]
      v <- vals[ord]
      u <- unique(v)
      if (length(u) > 1L) varies <- TRUE
      # Contiguous runs: each value appears in exactly one block.
      if (length(rle(v)$values) != length(u)) {
        return(FALSE)
      }
    }
    varies
  }, logical(1))

  hit <- cand[ok]
  if (length(hit) == 1L) hit else NULL
}


# ---- the selector ----------------------------------------------------------

#' Decide the figure for a tidy long table.
#'
#' @param df tidy long data: one row per observation.
#' @param x,series,value,unit,partition column names; NULL means auto-detect.
#'   Pass partition = NA to suppress partition detection.
#' @return a chart_spec: structural decisions plus a `notes` trail explaining
#'   each one.
pick_chart <- function(df, x = NULL, series = NULL, value = "value",
                       unit = "unit", partition = NULL) {
  stopifnot(is.data.frame(df), nrow(df) > 0L)

  if (is.null(x)) x <- detect_column(df, X_CANDIDATES, "x")
  if (is.null(x)) stop("No x column found. Pass x = explicitly.", call. = FALSE)
  if (is.null(series)) series <- detect_column(df, SERIES_CANDIDATES, "series")
  if (!value %in% names(df)) stop("No ", sQuote(value), " column.", call. = FALSE)
  if (!unit %in% names(df)) unit <- NULL

  notes <- character()
  note <- function(...) notes <<- c(notes, paste0(...))

  # --- features ---
  x_type <- classify_x(df[[x]])
  note("x column ", sQuote(x), " classifies as ", x_type, ".")

  keys <- if (is.null(series)) "(single)" else unique(as.character(df[[series]]))
  n_series <- length(keys)
  note(n_series, " series", if (!is.null(series)) paste0(" from ", sQuote(series)) else " (no series column)", ".")

  if (n_series > CHART_MAX_SERIES) {
    stop(
      "Refusing to pick a chart for ", n_series, " series (limit ",
      CHART_MAX_SERIES, "). A categorical palette cannot carry this many. ",
      "Facet, aggregate, or select a subset first.",
      call. = FALSE
    )
  }

  units <- if (is.null(unit)) character() else unique(as.character(df[[unit]]))
  n_units <- max(length(units), 1L)
  note(n_units, " distinct unit", if (n_units == 1L) "" else "s",
       if (length(units)) paste0(": ", paste(sQuote(units), collapse = ", ")) else "", ".")

  if (is.null(partition)) {
    partition <- detect_partition(df, x, series, value, unit)
    if (!is.null(partition)) {
      note("Detected partition column ", sQuote(partition),
           ": series are split into segments and never interpolated across.")
    }
  } else if (length(partition) == 1L && is.na(partition)) {
    partition <- NULL
    note("Partition detection suppressed by caller.")
  }

  per_series <- if (is.null(series)) {
    length(unique(df[[x]]))
  } else {
    max(tapply(df[[x]], df[[series]], function(v) length(unique(v))))
  }
  note("Densest series carries ", per_series, " points.")

  # Non-numeric values in a numeric column are agency sentinels, not data. CDC
  # writes "Suppressed" where a count falls below its disclosure threshold. They
  # must render as gaps: dropping them silently joins across the gap, and
  # coercing them to zero (which is what EPA's own Figure 2 does) states a rate
  # of zero deaths where the truth is that the rate is unpublished.
  raw_vals <- trimws(as.character(df[[value]]))
  is_blank <- is.na(raw_vals) | raw_vals == ""
  numeric_ok <- !is.na(suppressWarnings(as.numeric(raw_vals)))
  sentinels <- unique(raw_vals[!is_blank & !numeric_ok])

  # Upstream may already have split markers into a flag column (see
  # split_value_flag() in epa_csv.R), leaving value blank where flag is set.
  flag_col <- intersect(c("flag", "value_flag"), names(df))[1]
  if (!is.na(flag_col)) {
    fl <- trimws(as.character(df[[flag_col]]))
    sentinels <- unique(c(sentinels, fl[!is.na(fl) & fl != ""]))
  }

  gaps <- if (!is.na(flag_col)) {
    sum(!is.na(df[[flag_col]]) & trimws(as.character(df[[flag_col]])) != "")
  } else {
    sum(!is_blank & !numeric_ok)
  }

  if (length(sentinels)) {
    note("Suppression marker", if (length(sentinels) == 1L) "" else "s", " present (",
         paste(sQuote(sentinels), collapse = ", "), ") on ", gaps, " observation",
         if (gaps == 1L) "" else "s",
         ". These render as gaps: never zero, never joined across.")
  }

  # --- rules ---
  chart <- if (x_type %in% c("year", "date", "numeric")) "line" else "bar"
  note("Rule: x is ", x_type, " -> ", chart, ".")

  layout <- if (n_units > 1L) "small_multiples" else "single"
  if (layout == "small_multiples") {
    note("Rule: ", n_units, " units -> ", n_units,
         " stacked panels sharing the x axis. A dual axis is not used, ",
         "so no rescaling constant exists to get wrong.")
  } else {
    note("Rule: one unit -> one panel.")
  }

  show_points <- per_series <= CHART_DENSE_POINTS
  note("Rule: ", per_series, if (show_points) " <= " else " > ", CHART_DENSE_POINTS,
       " -> ", if (show_points) "show point markers." else "no markers, thin stroke.")

  label_style <- if (n_series <= CHART_DIRECT_LABEL_MAX && n_series > 1L) {
    "direct"
  } else if (n_series == 1L) {
    "none"
  } else {
    "legend"
  }
  note("Rule: ", n_series, " series -> ", label_style, " labelling.")

  # Series order: descending mean value. Mechanical, and it puts the topmost
  # line first in any legend or label stack so reading order matches the chart.
  series_order <- keys
  if (!is.null(series)) {
    num <- suppressWarnings(as.numeric(as.character(df[[value]])))
    m <- tapply(num, as.character(df[[series]]), function(v) mean(v, na.rm = TRUE))
    series_order <- names(sort(m, decreasing = TRUE))
    note("Series ordered by descending mean value: ", paste(series_order, collapse = " > "), ".")
  }

  # Which series actually break.
  broken <- character()
  if (!is.null(partition) && !is.null(series)) {
    broken <- names(which(tapply(
      as.character(df[[partition]]), as.character(df[[series]]),
      function(v) length(unique(v)) > 1L
    )))
    if (length(broken)) {
      note("Series broken by ", sQuote(partition), ": ", paste(broken, collapse = ", "), ".")
    }
  }

  # Panel assignment, by unit, ordered by first appearance.
  panels <- if (layout == "small_multiples") units[order(match(units, as.character(df[[unit]])))] else units

  structure(
    list(
      chart        = chart,
      layout       = layout,
      panels       = panels,
      n_panels     = if (layout == "small_multiples") n_units else 1L,
      x            = x,
      x_type       = x_type,
      series       = series,
      value        = value,
      unit         = unit,
      partition    = partition,
      group_expr   = if (is.null(partition)) series else paste0(series, " + ", partition),
      series_order = series_order,
      n_series     = n_series,
      n_points_max = per_series,
      show_points  = show_points,
      label_style  = label_style,
      broken       = broken,
      sentinels    = sentinels,
      n_gaps       = gaps,
      notes        = notes
    ),
    class = "chart_spec"
  )
}

#' @export
print.chart_spec <- function(x, ...) {
  cat("<chart_spec>\n")
  cat("  chart       :", x$chart, "\n")
  cat("  layout      :", x$layout, sprintf("(%d panel%s)", x$n_panels, if (x$n_panels == 1L) "" else "s"), "\n")
  if (x$n_panels > 1L) cat("  panels      :", paste(x$panels, collapse = " | "), "\n")
  cat("  x           :", x$x, sprintf("(%s)", x$x_type), "\n")
  cat("  series      :", x$series %||% "(none)", sprintf("[n=%d]", x$n_series), "\n")
  cat("  order       :", paste(x$series_order, collapse = " > "), "\n")
  cat("  partition   :", x$partition %||% "(none)", "\n")
  if (length(x$broken)) cat("  broken      :", paste(x$broken, collapse = ", "), "\n")
  cat("  points      :", if (x$show_points) "markers" else "no markers", sprintf("(max %d/series)", x$n_points_max), "\n")
  cat("  labelling   :", x$label_style, "\n")
  cat("  why:\n")
  for (n in x$notes) cat("    -", n, "\n")
  invisible(x)
}
