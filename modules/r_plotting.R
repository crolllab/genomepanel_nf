library(ggplot2)
library(dplyr)

# -----------------------------------------------
# Helper: capture a ggplot as an inline base64 PDF <embed> tag
# Uses R's built-in PDF device with embedded Type-1 fonts (Helvetica).
# No system fonts required - works in any container or OS.
# All modern browsers render inline PDFs natively.
# -----------------------------------------------
plot_to_embed <- function(p, width = 7, height = 5) {
  tmp <- tempfile(fileext = ".pdf")
  pdf(tmp, width = width, height = height, useDingbats = FALSE)
  print(p)
  dev.off()
  raw_bytes <- readBin(tmp, "raw", file.info(tmp)[["size"]])
  b64 <- base64enc::base64encode(raw_bytes)
  paste0('<embed src="data:application/pdf;base64,', b64,
         '" type="application/pdf"',
         ' width="', round(width * 96), '"',
         ' height="', round(height * 96), '"',
         ' style="border:none;">')
}

# -----------------------------------------------
# Helper: shorten sample names (keep prefix before first underscore).
# Falls back to full names if abbreviation would produce duplicates.
# -----------------------------------------------
short_name <- function(x) {
  short <- sub("_.*", "", x)
  if (anyDuplicated(short)) x else short
}

# -----------------------------------------------
# Helper: read a pipeline summary TSV (wide format, row names in col 1,
# sample names in header). Handles duplicate row names safely.
# Returns list: $keys (character), $vals (numeric matrix), $samples (character)
# -----------------------------------------------
read_summary_tsv <- function(f) {
  lines <- readLines(f, warn = FALSE)
  if (length(lines) < 2) return(NULL)
  hdr <- strsplit(lines[1], "\t", fixed = TRUE)[[1]]
  samples <- hdr[nchar(trimws(hdr)) > 0]
  body <- lapply(lines[-1], function(l) {
    cells <- strsplit(l, "\t", fixed = TRUE)[[1]]
    list(key = trimws(cells[1]),
         vals = suppressWarnings(as.numeric(cells[-1])))
  })
  keys <- vapply(body, `[[`, character(1), "key")
  vals <- do.call(rbind, lapply(body, `[[`, "vals"))
  colnames(vals) <- samples
  list(keys = keys, vals = vals, samples = samples)
}

# Helper: extract a row by key name (n = nth occurrence)
get_row <- function(tsv, key, n = 1L) {
  idx <- which(tsv[["keys"]] == key)
  if (length(idx) < n) return(rep(NA_real_, length(tsv[["samples"]])))
  as.numeric(tsv[["vals"]][idx[[n]], ])
}

# -----------------------------------------------
# Accessible color palette (Okabe-Ito based, colorblind-safe)
# -----------------------------------------------
COL_BLUE      <- "#0072B2"   # primary blue
COL_SKYBLUE   <- "#56B4E9"   # light blue
COL_ORANGE    <- "#E69F00"   # orange
COL_AMBER     <- "#F5D270"   # light amber
COL_BLUE_DARK <- "#00456E"   # dark blue (jitter/borders)
COL_THRESH    <- "#D55E00"   # vermilion (threshold lines)

# -----------------------------------------------
# Read pipeline metadata written by r_plotting.nf
# -----------------------------------------------
meta_lines <- if (file.exists("pipeline_meta.txt")) readLines("pipeline_meta.txt", warn = FALSE) else character(0)
get_meta <- function(key, default) {
  m <- grep(paste0("^", key, "\t"), meta_lines, value = TRUE)
  if (length(m)) trimws(sub(paste0("^", key, "\t"), "", m[1])) else default
}
pipeline_version <- get_meta("version", "unknown")
report_date      <- get_meta("report_date", format(Sys.time(), "%Y-%m-%d %H:%M"))
pipeline_start   <- get_meta("pipeline_start", NA_character_)

# Compute approximate runtime
if (!is.na(pipeline_start)) {
  t0 <- as.POSIXct(pipeline_start, format = "%Y-%m-%d %H:%M")
  elapsed_min <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  if (elapsed_min < 60) {
    runtime_str <- sprintf("Runtime: ~%d min", round(elapsed_min))
  } else {
    runtime_str <- sprintf("Runtime: ~%.1f h", elapsed_min / 60)
  }
} else {
  runtime_str <- NULL
}

con <- file("pipeline_report.html", "w")

cat(paste0('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Variant calling QC report \u2014 genomepanel_nf v', pipeline_version, '</title>
<style>
body   { font-family: Arial, Helvetica, sans-serif; max-width: 1400px;
         margin: auto; padding: 20px 40px; color: #333; }
h1     { color: #1a237e; border-bottom: none;
         padding-bottom: 4px; margin-bottom: 4px; }
h2     { color: #283593; margin-top: 40px; margin-bottom: 8px; }
p      { max-width: 860px; line-height: 1.6; color: #555;
         margin-bottom: 20px; }
section { margin-bottom: 50px; }
.subtitle { font-size: 0.9em; color: #777; margin-top: 0; margin-bottom: 28px;
            border-bottom: 2px solid #1a237e; padding-bottom: 8px; }
.subtitle a { color: #5c6bc0; text-decoration: none; }
.subtitle a:hover { text-decoration: underline; }
.plot-row { display: flex; gap: 24px; align-items: flex-start;
            flex-wrap: wrap; }
img    { max-width: 100%; height: auto; }
table.summary { border-collapse: collapse; margin: 16px 0; min-width: 320px; }
table.summary th, table.summary td { border: 1px solid #ccc; padding: 8px 18px;
  text-align: left; font-size: 0.95em; }
table.summary thead tr { background: #e8eaf6; font-weight: bold; }
table.summary tbody tr:nth-child(even) { background: #f5f5f5; }
table.summary td:last-child { text-align: right; font-variant-numeric: tabular-nums; }
.alert { background: #fff3e0; border-left: 5px solid #ef6c00; padding: 4px 20px 14px;
         margin: 16px 0; border-radius: 3px; }
.alert p { color: #6d4c41; margin-bottom: 12px; }
.ok    { background: #e8f5e9; border-left: 5px solid #2e7d32; padding: 12px 20px;
         margin: 16px 0; border-radius: 3px; color: #1b5e20; }
ul.samples { columns: 4; -webkit-columns: 4; -moz-columns: 4; max-width: 860px;
             color: #555; line-height: 1.7; font-family: monospace;
             margin: 0 0 8px 0; padding-left: 20px; }
footer { margin-top: 60px; font-size: 0.85em; color: #aaa;
         border-top: 1px solid #eee; padding-top: 12px; }
</style>
</head>
<body>
<h1>Variant calling QC report</h1>
<p class="subtitle">genomepanel_nf <span style="color:#5c6bc0">v', pipeline_version, '</span> &middot; Generated: ', report_date,
  if (!is.null(runtime_str)) paste0(' &middot; ', runtime_str) else '',
  ' &middot; <a href="https://crolllab.github.io/genomepanel_nf/" target="_blank">Documentation</a></p>
'), file = con)

# =====================================================
# SECTION 0: Samples dropped during the run
# =====================================================
# Downloading and trimming fall back to an 'ignore' error strategy once their
# retries are exhausted, so a failed sample disappears from the run without
# failing it. ReportIgnoredSamples writes the names it detected; surface them
# here so a green run does not hide a shrunken panel.
if (file.exists("ignored_samples.txt")) {
  ig_lines   <- readLines("ignored_samples.txt", warn = FALSE)
  ig_section <- NA_character_
  ig_dl      <- character(0)
  ig_trim    <- character(0)

  for (ln in ig_lines) {
    if (grepl("^## Failed to download", ln))          { ig_section <- "dl";   next }
    if (grepl("^## Failed during read trimming", ln)) { ig_section <- "trim"; next }
    if (grepl("^\\s*#", ln) || !nzchar(trimws(ln)))    next
    if (identical(ig_section, "dl"))   ig_dl   <- c(ig_dl,   trimws(ln))
    if (identical(ig_section, "trim")) ig_trim <- c(ig_trim, trimws(ln))
  }

  n_drop <- length(ig_dl) + length(ig_trim)

  sample_list <- function(ids) {
    esc <- gsub("&", "&amp;", ids, fixed = TRUE)
    esc <- gsub("<", "&lt;",  esc, fixed = TRUE)
    esc <- gsub(">", "&gt;",  esc, fixed = TRUE)
    paste0('<ul class="samples">',
           paste0("<li>", esc, "</li>", collapse = ""),
           '</ul>\n')
  }

  cat('<section>\n<h2>Sample completeness</h2>\n', file = con)

  if (n_drop == 0) {
    cat('<div class="ok">Every sample that entered the run completed read
         processing. No samples were dropped.</div>\n', file = con)
  } else {
    cat(sprintf('<p><strong>%d sample(s) were dropped before variant calling
      and are absent from the final VCF.</strong> These steps give up rather than
      abort the run, so the pipeline still reports success. The same list is
      written to <code>1_sra_downloads/ignored_samples.txt</code>.</p>\n',
      n_drop), file = con)

    if (length(ig_dl) > 0) {
      cat('<div class="alert">\n', file = con)
      cat(sprintf('<p><strong>Failed to download (%d)</strong> &mdash; the
        accession was resolved, but the download exhausted its retries. Re-run to
        try again, or fetch the reads manually and pass them with
        <code>--reads</code>.</p>\n', length(ig_dl)), file = con)
      cat(sample_list(ig_dl), file = con)
      cat('</div>\n', file = con)
    }

    if (length(ig_trim) > 0) {
      cat('<div class="alert">\n', file = con)
      cat(sprintf('<p><strong>Failed during read trimming (%d)</strong> &mdash;
        reads were available but trimming exhausted its retries. Usually a
        truncated or corrupt FASTQ, or an out-of-memory kill.</p>\n',
        length(ig_trim)), file = con)
      cat(sample_list(ig_trim), file = con)
      cat('</div>\n', file = con)
    }
  }

  cat('</section>\n', file = con)
}

# =====================================================
# SECTION 1: Fastp base filtering (from fastp_summary.tsv)
# =====================================================
if (file.exists("fastp_summary.tsv")) {
  ft <- read_summary_tsv("fastp_summary.tsv")
} else {
  ft <- NULL
}

if (!is.null(ft) && length(ft[["samples"]]) > 0) {
  # total_bases appears twice: [1] before_filtering, [2] after_filtering
  before_gb <- get_row(ft, "total_bases", 1L) / 1e9
  after_gb <- get_row(ft, "total_bases", 2L) / 1e9
  # q20/q30 rates appear twice: [1] before, [2] after filtering
  q20_before <- get_row(ft, "q20_rate", 1L) * 100
  q20_after <- get_row(ft, "q20_rate", 2L) * 100
  q30_before <- get_row(ft, "q30_rate", 1L) * 100
  q30_after <- get_row(ft, "q30_rate", 2L) * 100

  samples <- ft[["samples"]]
  short <- short_name(samples)

  fdf <- data.frame(sample = samples,
                    short = short,
                    before_gb = before_gb,
                    after_gb = after_gb,
                    ret_pct = after_gb / before_gb * 100,
                    q20_before = q20_before,
                    q20_after  = q20_after,
                    q30_before = q30_before,
                    q30_after  = q30_after,
                    stringsAsFactors = FALSE)
  fdf <- fdf[order(fdf[["before_gb"]], decreasing = TRUE), ]
  fdf[["short"]] <- factor(fdf[["short"]], levels = unique(fdf[["short"]]))

  flong <- rbind(
    data.frame(short = fdf[["short"]], value = fdf[["after_gb"]],
               category = "Retained"),
    data.frame(short = fdf[["short"]],
               value = fdf[["before_gb"]] - fdf[["after_gb"]],
               category = "Filtered out")
  )
  flong[["category"]] <- factor(flong[["category"]],
                                 levels = c("Filtered out", "Retained"))

  p1a <- ggplot(flong, aes(x = short, y = value, fill = category)) +
    geom_col() +
    scale_fill_manual(values = c("Retained" = COL_BLUE,
                                 "Filtered out" = COL_ORANGE)) +
    labs(x = NULL, y = "Gigabases", fill = NULL,
         title = "Bases retained per sample (fastp)") +
    theme_bw(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")

  qdf <- rbind(
    data.frame(short = fdf[["short"]], rate = fdf[["q20_before"]], metric = "Q20 (before)"),
    data.frame(short = fdf[["short"]], rate = fdf[["q20_after"]],  metric = "Q20 (after)"),
    data.frame(short = fdf[["short"]], rate = fdf[["q30_before"]], metric = "Q30 (before)"),
    data.frame(short = fdf[["short"]], rate = fdf[["q30_after"]],  metric = "Q30 (after)")
  )
  qdf[["metric"]] <- factor(qdf[["metric"]],
                             levels = c("Q20 (before)", "Q20 (after)",
                                        "Q30 (before)", "Q30 (after)"))

  p1b <- ggplot(qdf, aes(x = short, y = rate, color = metric,
                         group = metric)) +
    geom_line(alpha = 0.5) +
    geom_point(size = 2.5) +
    scale_color_manual(values = c("Q20 (before)" = COL_SKYBLUE,
                                  "Q20 (after)" = COL_BLUE,
                                  "Q30 (before)" = COL_AMBER,
                                  "Q30 (after)" = COL_ORANGE)) +
    scale_y_continuous(limits = c(0, 100)) +
    labs(x = NULL, y = "Rate (%)", color = NULL,
         title = "Q20/Q30 base quality rates") +
    theme_bw(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")

  cat('<section>
<h2>Read filtering summary (fastp)</h2>
<p>Stacked bars show bases retained (blue) and filtered out (orange) per sample,
sorted by total input gigabases in descending order.
The line plot shows Q20 and Q30 base-quality rates before and after adapter
trimming and quality filtering for each sample.</p>
<div class="plot-row">
', file = con)
  cat(plot_to_embed(p1a, 7, 5), file = con)
  cat(plot_to_embed(p1b, 7, 5), file = con)
  cat('</div></section>\n', file = con)
}

# =====================================================
# SECTION 2: BWA mapping statistics (from bwa_summary.tsv)
# =====================================================
if (file.exists("bwa_summary.tsv")) {
  bt <- read_summary_tsv("bwa_summary.tsv")
} else {
  bt <- NULL
}

if (!is.null(bt) && length(bt[["samples"]]) > 0) {
  # "primary" and "mapped %" first occurrence = QC-passed reads section
  primary <- get_row(bt, "primary", 1L)
  mapped_pct <- get_row(bt, "mapped %", 1L)

  samples <- bt[["samples"]]
  short <- short_name(samples)

  bdf <- data.frame(sample = samples,
                    short = short,
                    primary = primary,
                    mapped_pct = mapped_pct,
                    stringsAsFactors = FALSE)
  bdf <- bdf[order(bdf[["mapped_pct"]], decreasing = TRUE), ]
  bdf[["short"]] <- factor(bdf[["short"]], levels = unique(bdf[["short"]]))

  # Auto-zoom y-axis: start just below the minimum value, cap at 100
  y_min <- max(0, floor(min(bdf[["mapped_pct"]], na.rm = TRUE) / 5) * 5 - 5)
  y_max <- 100

  y_pad <- (y_max - y_min) * 0.08

  p2a <- ggplot(bdf, aes(x = short, y = mapped_pct,
                         size = primary / 1e6)) +
    geom_point(shape = 21, fill = COL_BLUE,
               color = COL_BLUE_DARK, alpha = 0.75) +
    scale_size_continuous(name = "Primary reads (M)", range = c(4, 14)) +
    coord_cartesian(ylim = c(y_min, y_max + y_pad)) +
    labs(x = NULL, y = "Mapping rate (%)",
         title = "BWA-MEM2 mapping rate per sample") +
    theme_bw(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")

  p2b <- ggplot(bdf, aes(x = factor(1), y = mapped_pct)) +
    geom_violin(fill = COL_BLUE, alpha = 0.45, color = NA,
                trim = FALSE) +
    geom_jitter(width = 0.09, size = 2.5, alpha = 0.8,
                color = COL_BLUE_DARK) +
    coord_cartesian(ylim = c(y_min, y_max + y_pad)) +
    labs(x = NULL, y = "Mapping rate (%)",
         title = "Distribution of\nmapping rates") +
    theme_bw(base_size = 12) +
    theme(axis.text.x = element_blank(),
          axis.ticks.x = element_blank())

  cat('<section>
<h2>Alignment statistics (BWA-MEM2)</h2>
<p>Each circle represents one sample, sorted by mapping rate in descending order. Circle area scales with the total number
of primary reads (QC-passed). The y-axis shows the percentage of primary reads
that mapped to the reference genome.
The violin plot shows the distribution of mapping rates across all samples.</p>
<div class="plot-row">
', file = con)
  cat(plot_to_embed(p2a, 7, 5), file = con)
  cat(plot_to_embed(p2b, 3.5, 5), file = con)
  cat('</div></section>\n', file = con)
}

# =====================================================
# =====================================================
# SECTION 3: Variant summary table
# =====================================================
if (file.exists("final_variants.variant_stats.tsv")) {
  vstats <- tryCatch(
    read.table("final_variants.variant_stats.tsv", header = TRUE, sep = "\t",
               stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
  if (!is.null(vstats) && nrow(vstats) > 0) {
    cat('<section>\n<h2>Variant summary</h2>\n', file = con)
    cat('<p>Counts of SNPs and indels before and after hard-filter quality thresholds.
PASS variants passed all filters and are written to the final clean VCF.</p>\n', file = con)
    cat('<table class="summary">\n<thead><tr><th>Category</th><th>Count</th></tr></thead>\n<tbody>\n', file = con)
    for (i in seq_len(nrow(vstats))) {
      cat(sprintf('<tr><td>%s</td><td>%s</td></tr>\n',
                  vstats[i, 1], format(as.integer(vstats[i, 2]), big.mark = ",")), file = con)
    }
    cat('</tbody>\n</table>\n</section>\n', file = con)
  }
}

# =====================================================
# SECTION 4: Variant quality metrics
# Skip gracefully if metrics file is empty or malformed.
# =====================================================
df <- NULL
if (file.exists("final_variants.metrics.csv.gz")) {
  df <- tryCatch(
    read.csv("final_variants.metrics.csv.gz", header = FALSE,
             stringsAsFactors = FALSE),
    error = function(e) NULL
  )
}

if (!is.null(df) && nrow(df) > 0 && ncol(df) >= 7) {
  names(df) <- c("CHROM", "POS", "QUAL", "AN", "MQ", "DP", "QD")
  df[["QD"]] <- suppressWarnings(as.numeric(df[["QD"]]))

  p3a <- ggplot(df, aes(x = QUAL)) +
    geom_density(fill = COL_SKYBLUE, alpha = 0.4, colour = COL_BLUE) +
    scale_x_log10() +
    geom_vline(xintercept = 1000, colour = COL_THRESH,
               linetype = "dashed", linewidth = 0.7) +
    labs(x = "QUAL (log10)", y = "Density") +
    theme_bw(base_size = 12)

  p3b <- ggplot(df, aes(x = AN)) +
    geom_density(fill = COL_SKYBLUE, alpha = 0.4, colour = COL_BLUE) +
    labs(x = "AN", y = "Density") +
    theme_bw(base_size = 12)

  p3c <- ggplot(df, aes(x = MQ)) +
    geom_density(fill = COL_SKYBLUE, alpha = 0.4, colour = COL_BLUE) +
    geom_vline(xintercept = 30, colour = COL_THRESH,
               linetype = "dashed", linewidth = 0.7) +
    labs(x = "MQ", y = "Density") +
    theme_bw(base_size = 12)

  p3d <- ggplot(df, aes(x = DP)) +
    geom_density(fill = COL_SKYBLUE, alpha = 0.4, colour = COL_BLUE) +
    scale_x_log10() +
    labs(x = "DP (log10)", y = "Density") +
    theme_bw(base_size = 12)

  p3e <- ggplot(df, aes(x = QD)) +
    geom_density(fill = COL_SKYBLUE, alpha = 0.4, colour = COL_BLUE) +
    geom_vline(xintercept = 20, colour = COL_THRESH,
               linetype = "dashed", linewidth = 0.7) +
    labs(x = "QD", y = "Density") +
    theme_bw(base_size = 12)

  cat('<section>
<h2>Variant quality metrics</h2>
<p>Density distributions of per-variant quality metrics from the unfiltered
genotyped call set. Red dashed lines indicate the hard-filter thresholds
applied in the pipeline: QUAL >= 1,000; MQ >= 30; QD >= 20.
QUAL and DP are shown on a log10 scale.
AN (allele number) reflects genotyping completeness across all samples;
the theoretical maximum equals 2 x the number of diploid samples.</p>
<div class="plot-row">
', file = con)
  cat(plot_to_embed(p3a, 4.5, 4), file = con)
  cat(plot_to_embed(p3b, 4.5, 4), file = con)
  cat(plot_to_embed(p3c, 4.5, 4), file = con)
  cat(plot_to_embed(p3d, 4.5, 4), file = con)
  cat(plot_to_embed(p3e, 4.5, 4), file = con)
  cat('</div></section>\n', file = con)
}

cat('<footer>Generated by genomepanel_nf</footer>
</body></html>', file = con)
close(con)
cat("pipeline_report.html written\n")
