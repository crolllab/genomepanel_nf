process RQualPlotting {
    time '24h'
    tag "Generating QC report with R"
    errorStrategy 'retry'
    maxRetries 3
    cpus 1
    memory '16GB'
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path concat_vcf
    path fastp_tsv
    path bwa_tsv

    output:
    path "pipeline_report.html", emit: report

    script:
    """
    cat > plot_pipeline.R << 'REOF'
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
    # Helper: shorten sample names (keep prefix before first underscore)
    # -----------------------------------------------
    short_name <- function(x) sub("_.*", "", x)

    # -----------------------------------------------
    # Helper: read a pipeline summary TSV (wide format, row names in col 1,
    # sample names in header). Handles duplicate row names safely.
    # Returns list: $keys (character), $vals (numeric matrix), $samples (character)
    # -----------------------------------------------
    read_summary_tsv <- function(f) {
      lines <- readLines(f, warn = FALSE)
      if (length(lines) < 2) return(NULL)
      hdr     <- strsplit(lines[1], "\t", fixed = TRUE)[[1]]
      samples <- hdr[nchar(trimws(hdr)) > 0]
      body    <- lapply(lines[-1], function(l) {
        cells <- strsplit(l, "\t", fixed = TRUE)[[1]]
        list(key  = trimws(cells[1]),
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

    con <- file("pipeline_report.html", "w")

    cat('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Pipeline QC Report</title>
<style>
body   { font-family: Arial, Helvetica, sans-serif; max-width: 1400px;
         margin: auto; padding: 20px 40px; color: #333; }
h1     { color: #1a237e; border-bottom: 2px solid #1a237e;
         padding-bottom: 8px; margin-bottom: 24px; }
h2     { color: #283593; margin-top: 40px; margin-bottom: 8px; }
p      { max-width: 860px; line-height: 1.6; color: #555;
         margin-bottom: 20px; }
section { margin-bottom: 50px; }
.plot-row { display: flex; gap: 24px; align-items: flex-start;
            flex-wrap: wrap; }
img    { max-width: 100%; height: auto; }
footer { margin-top: 60px; font-size: 0.85em; color: #aaa;
         border-top: 1px solid #eee; padding-top: 12px; }
</style>
</head>
<body>
<h1>Genome Panel Pipeline &#8212; Quality Control Report</h1>
', file = con)

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
      before_gb  <- get_row(ft, "total_bases", 1L) / 1e9
      after_gb   <- get_row(ft, "total_bases", 2L) / 1e9
      # q20/q30 rates appear twice: [1] before, [2] after filtering
      q20_before <- get_row(ft, "q20_rate", 1L) * 100
      q20_after  <- get_row(ft, "q20_rate", 2L) * 100
      q30_before <- get_row(ft, "q30_rate", 1L) * 100
      q30_after  <- get_row(ft, "q30_rate", 2L) * 100

      samples <- ft[["samples"]]
      short   <- short_name(samples)

      fdf <- data.frame(sample    = samples,
                        short     = short,
                        before_gb = before_gb,
                        after_gb  = after_gb,
                        ret_pct   = after_gb / before_gb * 100,
                        stringsAsFactors = FALSE)
      fdf <- fdf[order(fdf[["before_gb"]], decreasing = TRUE), ]
      fdf[["short"]] <- factor(fdf[["short"]], levels = fdf[["short"]])

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
        scale_fill_manual(values = c("Retained"     = "#43A047",
                                     "Filtered out" = "#E53935")) +
        labs(x = NULL, y = "Gigabases", fill = NULL,
             title = "Bases retained per sample (fastp)") +
        theme_bw(base_size = 12) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1),
              legend.position = "bottom")

      qdf <- rbind(
        data.frame(short = fdf[["short"]], rate = q20_before[order(fdf[["before_gb"]], decreasing = TRUE)],
                   metric = "Q20 (before)"),
        data.frame(short = fdf[["short"]], rate = q20_after[order(fdf[["before_gb"]], decreasing = TRUE)],
                   metric = "Q20 (after)"),
        data.frame(short = fdf[["short"]], rate = q30_before[order(fdf[["before_gb"]], decreasing = TRUE)],
                   metric = "Q30 (before)"),
        data.frame(short = fdf[["short"]], rate = q30_after[order(fdf[["before_gb"]], decreasing = TRUE)],
                   metric = "Q30 (after)")
      )
      qdf[["metric"]] <- factor(qdf[["metric"]],
                                levels = c("Q20 (before)", "Q20 (after)",
                                           "Q30 (before)", "Q30 (after)"))

      p1b <- ggplot(qdf, aes(x = short, y = rate, color = metric,
                              group = metric)) +
        geom_line(alpha = 0.5) +
        geom_point(size = 2.5) +
        scale_color_manual(values = c("Q20 (before)" = "#AED6F1",
                                      "Q20 (after)"  = "#1A73E8",
                                      "Q30 (before)" = "#FADBD8",
                                      "Q30 (after)"  = "#C0392B")) +
        scale_y_continuous(limits = c(0, 100)) +
        labs(x = NULL, y = "Rate (%)", color = NULL,
             title = "Q20/Q30 base quality rates") +
        theme_bw(base_size = 12) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1),
              legend.position = "bottom")

      cat('<section>
<h2>Read filtering summary (fastp)</h2>
<p>Stacked bars show bases retained (green) and filtered out (red) per sample,
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
      primary    <- get_row(bt, "primary",   1L)
      mapped_pct <- get_row(bt, "mapped %",  1L)

      samples <- bt[["samples"]]
      short   <- short_name(samples)

      bdf <- data.frame(sample     = samples,
                        short      = short,
                        primary    = primary,
                        mapped_pct = mapped_pct,
                        stringsAsFactors = FALSE)
      bdf <- bdf[order(bdf[["short"]]), ]
      bdf[["short"]] <- factor(bdf[["short"]], levels = bdf[["short"]])

      p2a <- ggplot(bdf, aes(x = short, y = mapped_pct,
                              size = primary / 1e6)) +
        geom_point(shape = 21, fill = "#1E88E5",
                   color = "black", alpha = 0.75) +
        scale_size_continuous(name = "Primary reads (M)", range = c(4, 18)) +
        scale_y_continuous(limits = c(0, 100), expand = c(0, 2)) +
        labs(x = NULL, y = "Mapping rate (%)",
             title = "BWA-MEM2 mapping rate per sample") +
        theme_bw(base_size = 12) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1),
              legend.position = "bottom")

      p2b <- ggplot(bdf, aes(x = factor(1), y = mapped_pct)) +
        geom_violin(fill = "#1E88E5", alpha = 0.45, color = NA,
                    trim = FALSE) +
        geom_jitter(width = 0.09, size = 2.5, alpha = 0.8,
                    color = "#0D47A1") +
        scale_y_continuous(limits = c(0, 100), expand = c(0.02, 0)) +
        labs(x = NULL, y = "Mapping rate (%)",
             title = "Distribution of\\nmapping rates") +
        theme_bw(base_size = 12) +
        theme(axis.text.x = element_blank(),
              axis.ticks.x = element_blank())

      cat('<section>
<h2>Alignment statistics (BWA-MEM2)</h2>
<p>Each circle represents one sample. Circle area scales with the total number
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
    # SECTION 3: Variant quality metrics
    # =====================================================
    if (file.exists("final_variants.metrics.csv.gz")) {

      df        <- read.csv("final_variants.metrics.csv.gz", header = FALSE,
                             stringsAsFactors = FALSE)
      names(df) <- c("CHROM", "POS", "QUAL", "AN", "MQ", "DP", "QD")
      df[["QD"]] <- suppressWarnings(as.numeric(df[["QD"]]))

      p3a <- ggplot(df, aes(x = QUAL)) +
        geom_density(fill = "#8E24AA", alpha = 0.4, colour = "#4A148C") +
        scale_x_log10() +
        geom_vline(xintercept = 1000, colour = "red",
                   linetype = "dashed", size = 0.7) +
        labs(x = "QUAL (log10)", y = "Density") +
        theme_bw(base_size = 12)

      p3b <- ggplot(df, aes(x = AN)) +
        geom_density(fill = "#8E24AA", alpha = 0.4, colour = "#4A148C") +
        labs(x = "AN", y = "Density") +
        theme_bw(base_size = 12)

      p3c <- ggplot(df, aes(x = MQ)) +
        geom_density(fill = "#8E24AA", alpha = 0.4, colour = "#4A148C") +
        geom_vline(xintercept = 30, colour = "red",
                   linetype = "dashed", size = 0.7) +
        labs(x = "MQ", y = "Density") +
        theme_bw(base_size = 12)

      p3d <- ggplot(df, aes(x = DP)) +
        geom_density(fill = "#8E24AA", alpha = 0.4, colour = "#4A148C") +
        scale_x_log10() +
        labs(x = "DP (log10)", y = "Density") +
        theme_bw(base_size = 12)

      p3e <- ggplot(df, aes(x = QD)) +
        geom_density(fill = "#8E24AA", alpha = 0.4, colour = "#4A148C") +
        geom_vline(xintercept = 20, colour = "red",
                   linetype = "dashed", size = 0.7) +
        labs(x = "QD", y = "Density") +
        theme_bw(base_size = 12)

      cat('<section>
<h2>Variant quality metrics</h2>
<p>Density distributions of per-variant quality metrics from the unfiltered
genotyped call set. Red dashed lines indicate the hard-filter thresholds
applied in the pipeline: QUAL &ge; 1,000; MQ &ge; 30; QD &ge; 20.
QUAL and DP are shown on a log<sub>10</sub> scale.
AN (allele number) reflects genotyping completeness across all samples;
the theoretical maximum equals 2 &times; the number of diploid samples.</p>
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
    cat("pipeline_report.html written\\n")
    REOF

    Rscript plot_pipeline.R
    """
}
