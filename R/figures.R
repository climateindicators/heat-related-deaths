# The three interactive figures for index.qmd.
#
# Sourced from a page's setup chunk, after _common.R. Each fig_*() function
# reads data/ (never data-raw/) and returns a girafe htmlwidget: build-time SVG,
# hover tooltips, no CDN dependency. See _common.R for INDICATOR_COLOURS and
# theme_indicator().
#
# These are built to represent the data honestly and read clearly, not to
# reproduce EPA's own chart design:
#
#   - Figure 2's suppressed years (2004, 2014, non-Hispanic Black) are NA in
#     read_indicator() and ggplot2's default geom_line does not connect across
#     an NA, so they draw as a gap rather than a false zero.
#   - The example figure uses two stacked panels sharing the x axis rather than
#     a dual y axis. A dual axis needs an arbitrary rescaling constant, and that
#     constant is where the classic bug lives: a tooltip on the rescaled series
#     reporting the other series' scale. With two panels there is no constant to
#     get wrong, and it matches the data's two distinct units (deaths,
#     degrees Fahrenheit) exactly. R/utils/pick_chart.R reaches the same
#     panelling decision from the data shape alone.
#   - Series are labelled with a plain legend above the plot rather than
#     end-of-line direct labels. Direct labels were tried first; with strings
#     this long ("Underlying and contributing causes of death (May-Sept)") a
#     collision-avoiding label fights the very lines it is meant to sit beside,
#     on a chart this narrow. The legend plus the hover tooltip (which names
#     the series on every point) plus the data table under each figure
#     together keep identity off colour alone.
#   - Colour is a fixed three-slot categorical palette (blue/orange/aqua),
#     validated for CVD-safe separation with dataviz/scripts/validate_palette.js,
#     assigned by role rather than cycled: blue is always the baseline series,
#     orange the one most worth the reader's attention, aqua a second
#     comparison series. See _common.R.

suppressPackageStartupMessages({
  library(ggiraph)
})

GIRAFE_OPTS <- list(
  opts_hover(css = "stroke-width:3.5;"),
  opts_hover_inv(css = "opacity:0.3;"),
  opts_tooltip(css = paste(
    "background:#1e1e1e;color:#fff;padding:6px 10px;border-radius:4px;",
    "font-family:sans-serif;font-size:12px;"
  )),
  opts_toolbar(saveaspng = FALSE),
  opts_sizing(rescale = TRUE, width = 1)
)

girafe_indicator <- function(p, height = 4.2) {
  ggiraph::girafe(
    ggobj = p, width_svg = 8, height_svg = height,
    options = GIRAFE_OPTS
  )
}

# Map a data frame's label column to INDICATOR_COLOURS and to a legend order,
# both driven by an explicit key order rather than alphabetising the label
# text. ggplot's default scale ordering is alphabetical for a character
# aesthetic, which happens to match EPA's own legend for Figure 1 and does not
# for Figure 2 (EPA orders by descending magnitude: Age 65+, Non-Hispanic
# Black, General population). Explicit is used everywhere so the correct order
# is not an accident.
label_colours <- function(d, key_col, label_col, order) {
  lab <- d[[label_col]][match(order, d[[key_col]])]
  setNames(unname(INDICATOR_COLOURS[order]), lab)
}
label_order <- function(d, key_col, label_col, order) {
  d[[label_col]][match(order, d[[key_col]])]
}

legend_top <- function() {
  theme(
    legend.position   = "top",
    legend.title      = element_blank(),
    legend.justification = "left",
    legend.margin     = margin(0, 0, 6, 0),
    legend.text       = element_text(size = rel(0.85)),
    legend.key.width  = unit(1.4, "lines")
  )
}

# ---- Figure 1: annual heat-related death rates -------------------------------

# *_plot() builds the plain ggplot object; fig_1()/fig_2()/fig_example() wrap it
# for the page. The split exists so the plot can be ggsave()'d for a static
# side-by-side comparison against data-raw/epa-figure-*.png without pulling in
# the htmlwidget machinery.
fig_1_plot <- function() {
  d <- read_indicator("heat_deaths_annual.csv")
  # icd_revision splits the line at the classification change; series_key alone
  # would draw straight through 1998/1999.
  d$seg <- paste(d$series_key, d$icd_revision, sep = "/")
  order <- c("underlying_or_contributing_may_sep", "underlying_all_year")

  ggplot(d, aes(x = year, y = value, colour = series_label, group = seg)) +
    geom_line_interactive(linewidth = 0.9) +
    geom_point_interactive(
      aes(
        data_id = series_key,
        tooltip = sprintf(
          "%d — %s\n%.2f deaths per million (%s)",
          year, series_label, value, icd_revision
        )
      ),
      size = 1.4
    ) +
    scale_colour_manual(values = label_colours(d, "series_key", "series_label", order),
                       breaks = label_order(d, "series_key", "series_label", order)) +
    guides(colour = guide_legend(nrow = 2, byrow = TRUE)) +
    scale_x_continuous(breaks = seq(1980, 2020, 10)) +
    scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.06))) +
    labs(x = NULL, y = "Death rate (per million people)") +
    theme_indicator() +
    legend_top()
}

fig_1 <- function() girafe_indicator(fig_1_plot())

fig_1_table <- function() {
  d <- read_indicator("heat_deaths_annual.csv")
  tidyr::pivot_wider(d, id_cols = year, names_from = series_label, values_from = value)
}

# ---- Figure 2: summer heat + cardiovascular disease death rates --------------

fig_2_plot <- function() {
  d <- read_indicator("heat_deaths_summer_cvd.csv")
  order <- c("age_65_plus", "nh_black", "general")
  d$population_key <- factor(d$population_key, levels = order)

  ggplot(d, aes(x = year, y = value, colour = population_label, group = population_key)) +
    geom_line_interactive(linewidth = 0.9) +
    geom_point_interactive(
      aes(
        data_id = population_key,
        tooltip = ifelse(
          flag == "suppressed",
          sprintf("%d — %s\nSuppressed: too few deaths to publish", year, population_label),
          sprintf("%d — %s\n%.2f deaths per million", year, population_label, value)
        )
      ),
      size = 1.3
    ) +
    scale_colour_manual(values = label_colours(d, "population_key", "population_label", order),
                       breaks = label_order(d, "population_key", "population_label", order)) +
    scale_x_continuous(breaks = seq(2000, 2020, 5)) +
    scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.06))) +
    labs(x = NULL, y = "Death rate (per million people)") +
    theme_indicator() +
    legend_top()
}

fig_2 <- function() girafe_indicator(fig_2_plot())

fig_2_table <- function() {
  d <- read_indicator("heat_deaths_summer_cvd.csv")
  tidyr::pivot_wider(d, id_cols = year, names_from = population_label, values_from = value)
}

# ---- Example figure: 1995 Chicago heat wave -----------------------------------

# Strip labels for the two stacked panels, keyed on the unit value in data/,
# never on panel position.
EXAMPLE_PANEL_LABELS <- c(
  "deaths"             = "Number of daily deaths",
  "degrees Fahrenheit" = paste0("Daily high temperature (", intToUtf8(0x00B0), "F)")
)

fig_example_plot <- function() {
  d <- read_indicator("chicago_1995_heat_wave.csv")
  d$panel <- factor(EXAMPLE_PANEL_LABELS[d$unit], levels = unname(EXAMPLE_PANEL_LABELS))
  order <- c("deaths_1995", "deaths_avg_1990_2000", "high_temp_f")
  d$measure_key <- factor(d$measure_key, levels = order)

  # EPA highlights the severe stretch of the heat wave.
  highlight <- data.frame(xmin = as.Date("1995-07-11"), xmax = as.Date("1995-07-27"))

  # group is explicit because the tooltip string below is unique per row; left
  # implicit, ggplot infers grouping from every discrete aesthetic in a layer,
  # including tooltip, which would put each point in its own group of one and
  # silently break every line into isolated dots.
  ggplot(d, aes(x = date, y = value, colour = measure_label, group = measure_key)) +
    geom_rect(
      data = highlight, inherit.aes = FALSE,
      aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
      fill = "#2882e6", alpha = 0.08
    ) +
    geom_line_interactive(
      aes(
        data_id = measure_key, linetype = measure_key,
        tooltip = sprintf("%s\n%s: %.1f", format(date, "%B %d, %Y"), measure_label, value)
      ),
      linewidth = 0.8
    ) +
    facet_wrap(~panel, ncol = 1, scales = "free_y") +
    scale_colour_manual(
      values = label_colours(d, "measure_key", "measure_label", order),
      # The temperature series lives in its own facet and its meaning is
      # already carried by that facet's strip text, so it is left out of the
      # legend: a legend entry for it would sit above a panel it never appears
      # in.
      breaks = label_order(d, "measure_key", "measure_label", order[1:2])
    ) +
    scale_linetype_manual(
      values = setNames(c("solid", "solid", "22"), order),
      guide = "none"
    ) +
    scale_x_date(date_labels = "%b %d", date_breaks = "2 weeks") +
    labs(x = NULL, y = NULL) +
    theme_indicator() +
    legend_top() +
    theme(panel.spacing = unit(1, "lines"))
}

fig_example <- function() girafe_indicator(fig_example_plot(), height = 5.2)

fig_example_table <- function() {
  d <- read_indicator("chicago_1995_heat_wave.csv")
  tidyr::pivot_wider(d, id_cols = date, names_from = measure_label, values_from = value)
}
