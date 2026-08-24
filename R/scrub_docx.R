# One-time tool: remove reviewer-identifying metadata from a Word document
# before vendoring it into a public repo's data-raw/. Not part of the regular
# build; run once per source docx.
#
#   Rscript R/scrub_docx.R <in.docx> <out.docx>
#
# Removes, without touching visible paragraph text:
#   - word/comments.xml, word/people.xml, and the three MS comment-extension
#     parts, plus their relationships and content-type entries
#   - w:commentRangeStart/End and the w:r runs that exist only to hold a
#     w:commentReference
#   - w:del elements (deleted text and its w:author/w:date, entirely) and the
#     w:ins wrapper around inserted text (unwrapped, so the inserted text
#     itself is kept -- this is the accept-all-tracked-changes rendering)
#   - docProps/core.xml's <cp:lastModifiedBy>
#
# R/utils/read_docx.R already reconstructs the accept-all-tracked-changes text
# regardless of whether these markers are present (it excludes w:t with a
# w:del ancestor and never opens comments.xml), so this does not change what
# R/gen_narrative.R extracts. It exists only so the vendored file itself, if
# anyone opens it directly, carries no reviewer names.

suppressPackageStartupMessages({
  library(xml2)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: scrub_docx.R <in.docx> <out.docx>", call. = FALSE)
in_path  <- normalizePath(args[[1]], mustWork = TRUE)
out_path <- args[[2]]
if (!grepl("^([A-Za-z]:|/|\\\\)", out_path)) out_path <- file.path(getwd(), out_path)

W_NS  <- c(w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
R_NS  <- c(r = "http://schemas.openxmlformats.org/package/2006/relationships")
CT_NS <- c(c = "http://schemas.openxmlformats.org/package/2006/content-types")
CP_NS <- c(cp = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties")

tmp <- file.path(tempdir(), paste0("docxscrub_", as.integer(Sys.time())))
dir.create(tmp)
utils::unzip(in_path, exdir = tmp)

# ---- word/document.xml -----------------------------------------------------

doc_path <- file.path(tmp, "word", "document.xml")
doc <- read_xml(doc_path)

for (node in xml_find_all(doc, ".//w:r[w:commentReference]", W_NS)) xml_remove(node)
for (node in xml_find_all(doc, ".//w:commentRangeStart", W_NS)) xml_remove(node)
for (node in xml_find_all(doc, ".//w:commentRangeEnd", W_NS)) xml_remove(node)
for (node in xml_find_all(doc, ".//w:del", W_NS)) xml_remove(node)
for (node in xml_find_all(doc, ".//w:ins", W_NS)) {
  for (child in xml_children(node)) xml_add_sibling(node, child, .where = "before")
  xml_remove(node)
}

write_xml(doc, doc_path, options = character(0))

# ---- comment-related parts: delete if present ------------------------------

comment_parts <- c(
  "word/comments.xml", "word/commentsIds.xml",
  "word/commentsExtensible.xml", "word/commentsExtended.xml",
  "word/people.xml"
)
present <- comment_parts[file.exists(file.path(tmp, comment_parts))]
if (length(present)) {
  file.remove(file.path(tmp, present))

  # comments.xml's own rels part (e.g. hyperlinks cited inside comment text)
  # becomes orphaned once comments.xml is gone.
  comments_rels_path <- file.path(tmp, "word", "_rels", "comments.xml.rels")
  if (file.exists(comments_rels_path)) file.remove(comments_rels_path)

  rels_path <- file.path(tmp, "word", "_rels", "document.xml.rels")
  rels <- read_xml(rels_path)
  targets <- sub("^word/", "", present)
  for (t in targets) {
    for (node in xml_find_all(rels, sprintf(".//r:Relationship[@Target='%s']", t), R_NS)) {
      xml_remove(node)
    }
  }
  write_xml(rels, rels_path, options = character(0))

  ct_path <- file.path(tmp, "[Content_Types].xml")
  ct <- read_xml(ct_path)
  for (p in present) {
    part_name <- paste0("/", p)
    for (node in xml_find_all(ct, sprintf(".//c:Override[@PartName='%s']", part_name), CT_NS)) {
      xml_remove(node)
    }
  }
  write_xml(ct, ct_path, options = character(0))
}

# ---- docProps/core.xml: clear last-modified-by -----------------------------

core_path <- file.path(tmp, "docProps", "core.xml")
core <- read_xml(core_path)
for (node in xml_find_all(core, ".//cp:lastModifiedBy", CP_NS)) xml_text(node) <- ""
write_xml(core, core_path, options = character(0))

# ---- repackage --------------------------------------------------------------

old_wd <- setwd(tmp)
on.exit(setwd(old_wd), add = TRUE)
# all.files = TRUE is load-bearing. The default excludes dot-prefixed basenames,
# and "_rels/.rels" is one: it is the OPC package-relationship part, the entry
# point naming the main document. Omit it and the zip is not a valid Word
# document, even though R/utils/read_docx.R still parses it fine because it
# pulls word/document.xml straight out of the archive.
all_files <- list.files(".", recursive = TRUE, all.files = TRUE, no.. = TRUE)
if (file.exists(out_path)) file.remove(out_path)
zip::zip(out_path, files = all_files)
setwd(old_wd)

cat("Wrote:", out_path, "\n")
if (length(present)) cat("  removed parts:", paste(present, collapse = ", "), "\n")
