# Reader for EPA's indicator Word documents: word/document.xml only, parsed
# directly with xml2. Never officer::docx_summary() — it leaks deleted text
# (w:delText) in some documents, verified elsewhere in this project.
#
# The published EPA page equals the ACCEPT-ALL-TRACKED-CHANGES rendering of the
# source docx. So this reader:
#   - excludes any w:t (or w:br, w:tab) with a w:del ancestor
#   - never selects w:delText, w:delInstrText, or w:instrText at all (the last
#     carries Zotero ADDIN field codes)
#   - needs no special case for w:ins: its w:t has no w:del ancestor, so it is
#     selected naturally, in position
#   - folds a paragraph into the next one when its mark was deleted
#     (w:pPr/w:rPr/w:del)
#   - never opens comments.xml, people.xml, or any other part

suppressPackageStartupMessages({
  library(xml2)
})

W_NS <- c(w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

#' Load word/document.xml as an xml_document, encoding-safe.
#'
#' The raw bytes are handed to xml2::read_xml as a raw vector, not converted to
#' character first: rawToChar() would reinterpret the bytes in R's native
#' encoding before libxml2 ever sees the file's own UTF-8 declaration, turning
#' every curly quote and en dash into mojibake. This is the single most likely
#' silent failure in this whole file.
docx_body_xml <- function(path) {
  entry <- "word/document.xml"
  con <- unz(path, entry, open = "rb")
  on.exit(close(con), add = TRUE)
  size <- utils::unzip(path, list = TRUE)
  n <- size$Length[size$Name == entry]
  if (length(n) != 1L) stop("word/document.xml not found in ", path, call. = FALSE)
  xml2::read_xml(readBin(con, "raw", n = n))
}

#' Body paragraphs, absolute path so table cells / text boxes (none here, but
#' reused elsewhere) are never accidentally included.
docx_paragraphs_xml <- function(doc) {
  xml2::xml_find_all(doc, "/w:document/w:body/w:p", W_NS)
}

# Text-carrying leaves, excluding anything with a w:del ancestor. This single
# union expression is what keeps w:delText / w:delInstrText / w:instrText out
# entirely (they are never named, so ZOTERO field codes cannot leak) and needs
# no special case for w:ins (its w:t simply has no w:del ancestor).
LEAF_XPATH <- paste(
  ".//w:t[not(ancestor::w:del)]",
  ".//w:br[not(ancestor::w:del)]",
  ".//w:tab[not(ancestor::w:del)]",
  sep = " | "
)

#' Resolve a w:hyperlink's r:id against document.xml.rels.
docx_rels <- function(path) {
  entry <- "word/_rels/document.xml.rels"
  con <- unz(path, entry, open = "rb")
  on.exit(close(con), add = TRUE)
  size <- utils::unzip(path, list = TRUE)
  n <- size$Length[size$Name == entry]
  rels <- xml2::read_xml(readBin(con, "raw", n = n))
  ids <- xml2::xml_attr(xml2::xml_find_all(rels, "//*[local-name()='Relationship']"), "Id")
  targets <- xml2::xml_attr(xml2::xml_find_all(rels, "//*[local-name()='Relationship']"), "Target")
  stats::setNames(targets, ids)
}

# Markdown escaping for plain text, never applied to markers this reader adds.
md_escape <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  x <- gsub("([*_\\[\\]<>^~`])", "\\\\\\1", x, perl = TRUE)
  # A literal leading "*" or "-" would open a bullet list; two source
  # paragraphs in this document start with one (the ICD footnote, the Chicago
  # SMSA footnote).
  x <- sub("^([*+-])", "\\\\\\1", x)
  x
}

R_NS_URI <- "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

#' Render one paragraph's accepted text to a markdown string.
#'
#' Segments are built leaf by leaf, THEN merged where formatting is identical,
#' THEN escaped and wrapped. The merge matters: Word splits runs at arbitrary
#' boundaries (spellcheck state, revision save IDs), so a superscript like
#' "5,6" can arrive as two separate runs. Wrapping before merging would emit
#' "^5^^,6^", which Pandoc renders as two adjacent superscripts with a visible
#' break between them.
paragraph_markdown <- function(p, rels) {
  leaves <- xml2::xml_find_all(p, LEAF_XPATH, W_NS)
  if (length(leaves) == 0L) return("")

  seg <- lapply(leaves, function(leaf) {
    nm <- xml2::xml_name(leaf)
    text <- if (nm == "t") xml2::xml_text(leaf) else if (nm == "tab") "\t" else "\n"

    run <- xml2::xml_find_first(leaf, "ancestor::w:r[1]", W_NS)
    rpr <- if (!is.na(run)) xml2::xml_find_first(run, "./w:rPr", W_NS) else NA

    italic <- !is.na(rpr) && !is.na(xml2::xml_find_first(rpr, "./w:i", W_NS))
    bold   <- !is.na(rpr) && !is.na(xml2::xml_find_first(rpr, "./w:b", W_NS))
    valign <- if (!is.na(rpr)) {
      xml2::xml_attr(xml2::xml_find_first(rpr, "./w:vertAlign", W_NS), "val")
    } else NA_character_
    superscript <- identical(valign, "superscript")

    hl <- xml2::xml_find_first(leaf, "ancestor::w:hyperlink[1]", W_NS)
    href <- if (!is.na(hl)) {
      # The attribute is r:id (relationships namespace, local name "id"); xml2
      # requires the "prefix:localname" form, not the bare local name, or the
      # lookup silently returns NA and every hyperlink is dropped.
      rid <- xml2::xml_attr(hl, "r:id", ns = c(r = R_NS_URI))
      if (is.na(rid)) NA_character_ else unname(rels[rid])
    } else NA_character_

    list(text = text, italic = italic, bold = bold, superscript = superscript,
        href = if (length(href)) href else NA_character_)
  })

  # Merge adjacent segments that share every formatting attribute.
  merged <- list(seg[[1]])
  if (length(seg) > 1L) {
    for (i in 2:length(seg)) {
      last <- merged[[length(merged)]]
      cur  <- seg[[i]]
      same <- identical(last$italic, cur$italic) && identical(last$bold, cur$bold) &&
        identical(last$superscript, cur$superscript) && identical(last$href, cur$href)
      if (same) {
        merged[[length(merged)]]$text <- paste0(last$text, cur$text)
      } else {
        merged[[length(merged) + 1L]] <- cur
      }
    }
  }

  parts <- vapply(merged, function(s) {
    txt <- if (identical(s$text, "\t")) " " else if (identical(s$text, "\n")) "\\\n" else md_escape(s$text)
    if (!identical(s$text, "\t") && !identical(s$text, "\n")) {
      if (s$superscript) txt <- paste0("^", txt, "^")
      if (s$bold)         txt <- paste0("**", txt, "**")
      if (s$italic)        txt <- paste0("_", txt, "_")
      if (!is.na(s$href))  txt <- sprintf("[%s](%s)", txt, s$href)
    }
    txt
  }, character(1))

  paste(parts, collapse = "")
}

#' Read every body paragraph of a docx into a tidy frame, with the accept-all
#' rules applied and adjacent deleted-mark paragraphs folded together.
#'
#' @return tibble(i, style, text_md, text_plain, empty)
read_docx_paragraphs <- function(path) {
  doc  <- docx_body_xml(path)
  rels <- docx_rels(path)
  ps   <- docx_paragraphs_xml(doc)

  style <- vapply(ps, function(p) {
    s <- xml2::xml_find_first(p, "./w:pPr/w:pStyle", W_NS)
    if (is.na(s)) "Normal" else xml2::xml_attr(s, "val")
  }, character(1))

  mark_deleted <- vapply(ps, function(p) {
    !is.na(xml2::xml_find_first(p, "./w:pPr/w:rPr/w:del", W_NS))
  }, logical(1))

  text_md <- vapply(ps, paragraph_markdown, character(1), rels = rels)

  df <- data.frame(
    i = seq_along(ps), style = style, text_md = text_md,
    mark_deleted = mark_deleted, stringsAsFactors = FALSE
  )

  # Fold: a paragraph whose mark was deleted merges into the NEXT paragraph,
  # which keeps that next paragraph's own style. (0 occurrences in this
  # document; the path exists because it is the one that made officer leak
  # text elsewhere in this project, and it needs to be exercised by a
  # synthetic test, not just present.)
  i <- 1L
  while (i < nrow(df)) {
    if (df$mark_deleted[i]) {
      df$text_md[i + 1L] <- paste0(df$text_md[i], df$text_md[i + 1L])
      df <- df[-i, ]
    } else {
      i <- i + 1L
    }
  }
  df$mark_deleted <- NULL
  df$i <- seq_len(nrow(df))
  df$text_plain <- gsub("\\\\|\\*\\*|\\*|_|\\^|\\[|\\]\\([^)]*\\)", "", df$text_md)
  df$empty <- trimws(df$text_md) == ""
  df
}

#' Split paragraphs into named sections at Heading1/Heading2 boundaries.
#'
#' Returns a named list of paragraph-index vectors, keyed by the heading text.
#' Content before the first heading is under "".
docx_sections <- function(df, heading_styles = c("Heading1", "Heading2")) {
  is_head <- df$style %in% heading_styles
  head_idx <- df$i[is_head]
  head_txt <- df$text_plain[is_head]

  bounds <- c(head_idx, nrow(df) + 1L)
  sections <- list()
  if (length(head_idx) == 0L || head_idx[1] > 1L) {
    sections[[""]] <- seq_len(if (length(head_idx)) head_idx[1] - 1L else nrow(df))
  }
  for (k in seq_along(head_idx)) {
    rng <- (head_idx[k] + 1L):(bounds[k + 1L] - 1L)
    sections[[head_txt[k]]] <- if (length(rng) && rng[1] <= rng[length(rng)]) rng else integer(0)
  }
  sections
}
