# CNV summary tables from the per-sample gCNV output (see modules/r_cnv_summary.nf).
#
# Writes, all sorted by the contig order of the reference (.fai), then position:
#   cnv_segments.tsv        every segment of every sample (REF segments included)
#   cnv_contig_ploidy.tsv   per-sample, per-contig ploidy
#   cnv_sample_summary.tsv  per-sample counts of DEL/DUP segments
# and, with --annotation:
#   cnv_genes.tsv           gene x sample copy-number matrix
#   cnv_genes_long.tsv      one row per gene and sample, with call details

suppressPackageStartupMessages(library(data.table))

# ---------------------
# Arguments
# ---------------------
args <- commandArgs(trailingOnly = TRUE)
opt <- list()
for (i in seq(1, length(args), by = 2)) opt[[sub("^--", "", args[i])]] <- args[i + 1]

ref_cn       <- as.integer(opt[["ref-copy-number"]])
min_qs       <- as.numeric(opt[["min-qs"]])
annotation   <- opt[["annotation"]]
gene_feature <- opt[["gene-feature"]]

fai <- fread(opt[["fai"]], header = FALSE, select = 1:2, col.names = c("contig", "length"),
             colClasses = list(character = 1))
contig_order <- fai$contig

# Sort a table by reference contig order, then the given columns.
order_by_reference <- function(dt, ...) {
  dt[, contig_rank := match(contig, contig_order)]
  setorderv(dt, c("contig_rank", ...))
  dt[, contig_rank := NULL]
  invisible(dt)
}

# ---------------------
# VCF reading
# ---------------------
# gCNV VCFs have one sample column and a fixed FORMAT, so FORMAT is parsed
# once from the first record and applied to every row.
read_cnv_vcf <- function(path) {
  vcf <- fread(cmd = paste("zcat", shQuote(path), "| grep -v '^##'"), sep = "\t",
               header = TRUE, colClasses = list(character = c(1, 3:10)))
  setnames(vcf, 1, "CHROM")
  keys <- strsplit(vcf$FORMAT[1], ":", fixed = TRUE)[[1]]
  vals <- tstrsplit(vcf[[10]], ":", fixed = TRUE)
  out <- data.table(contig = vcf$CHROM,
                    start  = vcf$POS,
                    end    = as.integer(sub(".*END=([0-9]+).*", "\\1", vcf$INFO)),
                    alt    = vcf$ALT)
  for (k in seq_along(keys)) out[[keys[k]]] <- vals[[k]]
  out[]
}

intervals_files <- sort(list.files(pattern = "\\.cnv_intervals\\.vcf\\.gz$"))
segment_files   <- sort(list.files(pattern = "\\.cnv_segments\\.vcf\\.gz$"))
samples <- sub("\\.cnv_segments\\.vcf\\.gz$", "", segment_files)
if (length(samples) == 0) stop("No *.cnv_segments.vcf.gz files found.")

# ---------------------
# Segments
# ---------------------
# Each record carries a single ALT -- '.', <DEL> or <DUP> relative to the
# reference copy number (--ploidy) -- so GT is 0 or 1 and the ALT names the call.
segments <- rbindlist(lapply(seq_along(samples), function(i) {
  s <- read_cnv_vcf(segment_files[i])
  data.table(sample = samples[i], contig = s$contig, start = s$start, end = s$end,
             call   = fifelse(s$alt == "<DEL>", "DEL", fifelse(s$alt == "<DUP>", "DUP", "REF")),
             cn     = as.integer(s$CN),
             n_bins = as.integer(s$NP),
             qa     = as.numeric(s$QA),
             qs     = as.numeric(s$QS),
             qse    = as.numeric(s$QSE),
             qss    = as.numeric(s$QSS))
}))
segments[, filter := fifelse(qs >= min_qs, "PASS", "LowQual")]
order_by_reference(segments, c("start", "end", "sample"))
fwrite(segments, "cnv_segments.tsv", sep = "\t", quote = FALSE)

# ---------------------
# Contig ploidy
# ---------------------
ploidy_dirs <- list.dirs(opt[["ploidy-calls"]], recursive = FALSE)
ploidy <- rbindlist(lapply(ploidy_dirs[grepl("SAMPLE_[0-9]+$", ploidy_dirs)], function(d) {
  p <- fread(file.path(d, "contig_ploidy.tsv"), skip = "CONTIG", colClasses = list(character = 1))
  data.table(sample = readLines(file.path(d, "sample_name.txt"), warn = FALSE)[1],
             contig = p$CONTIG, ploidy = p$PLOIDY, ploidy_gq = p$PLOIDY_GQ)
}))
order_by_reference(ploidy, "sample")
fwrite(ploidy, "cnv_contig_ploidy.tsv", sep = "\t", quote = FALSE)

# ---------------------
# Per-sample summary
# ---------------------
sample_summary <- segments[, .(
  n_del            = sum(call == "DEL"),
  n_dup            = sum(call == "DUP"),
  bp_del           = sum(fifelse(call == "DEL", end - start + 1, 0)),
  bp_dup           = sum(fifelse(call == "DUP", end - start + 1, 0)),
  n_del_pass       = sum(call == "DEL" & filter == "PASS"),
  n_dup_pass       = sum(call == "DUP" & filter == "PASS"),
  contigs_off_ploidy = paste(ploidy[sample == .BY$sample & ploidy != ref_cn, contig], collapse = ",")
), by = sample]
setorder(sample_summary, sample)
fwrite(sample_summary, "cnv_sample_summary.tsv", sep = "\t", quote = FALSE)

# ---------------------
# Genes (--cnv_gene_annotation)
# ---------------------
if (is.null(annotation) || annotation == "" || annotation == "[]") quit(save = "no", status = 0)

# Anything after a ##FASTA line is sequence, not features; Windows line
# endings are dropped.
ann <- fread(cmd = paste("zcat -f", shQuote(annotation), "| tr -d '\\r' | awk -F'\\t' '/^##FASTA/ { exit } !/^#/ && NF >= 9'"),
             sep = "\t", header = FALSE, quote = "", select = c(1, 3:5, 7, 9),
             col.names = c("contig", "type", "start", "end", "strand", "attributes"),
             colClasses = list(character = c(1, 3, 7, 9)))
if (nrow(ann) == 0) stop("No features could be read from ", annotation, ".")
# GFF3 and GTF are told apart by their attribute syntax: key=value (GFF3)
# vs key "value" -- or key value, unquoted, as some tools write GTF.
is_gtf <- mean(grepl('^\\s*[^=;" ]+=', head(ann$attributes, 1000))) < 0.5

# One attribute's value per feature, NA where absent. GFF3 values are
# URL-decoded (%2C etc.) and only the first of several comma-separated
# Parents is kept.
attribute <- function(attrs, key) {
  pattern <- if (is_gtf) paste0('(^|;)\\s*', key, '\\s+"?([^";]*)"?') else paste0('(^|;)\\s*', key, '=([^;]*)')
  out <- rep(NA_character_, length(attrs))
  hit <- regexpr(pattern, attrs, perl = TRUE)
  out[hit > 0] <- trimws(sub(pattern, "\\2", regmatches(attrs, hit), perl = TRUE))
  if (!is_gtf) {
    out <- sub(",.*", "", out)
    enc <- !is.na(out) & grepl("%[0-9A-Fa-f]{2}", out)
    out[enc] <- vapply(out[enc], URLdecode, character(1))
  }
  out[!is.na(out) & out == ""] <- NA_character_
  out
}
first_of <- function(...) Reduce(function(a, b) fifelse(is.na(a), b, a), list(...))

# Genes come from the --cnv_gene_feature features. For the default "gene",
# every gene, transcript, exon and CDS line is grouped under the gene it
# belongs to -- following GFF3 Parent links up to the top-level feature (or
# gffread's geneID), or by GTF gene_id -- so it does not matter which levels
# an annotation contains: gene lines for some loci, bare transcripts or only
# exons/CDS for others, or one gene written over several lines. Sequence
# Ontology gene subtypes (protein_coding_gene, ncRNA_gene, pseudogene) count
# as genes.
gene_types <- if (gene_feature == "gene") {
  unique(c("gene", grep("_gene$", ann$type, value = TRUE), "pseudogene"))
} else gene_feature
use_types <- if (gene_feature == "gene") c(gene_types, "mRNA", "transcript", "exon", "CDS") else gene_feature
feat <- ann[type %in% use_types]
if (nrow(feat) == 0)
  stop("The annotation has no '", gene_feature, "' features",
       if (gene_feature == "gene") " (nor mRNA/transcript or exon/CDS features)",
       ". Feature types present: ", paste(head(sort(unique(ann$type)), 20), collapse = ", "),
       ". Choose one with --cnv_gene_feature.")

if (is_gtf) {
  feat[, gene_id := first_of(attribute(attributes, "gene_id"), attribute(attributes, "transcript_id"))]
  feat[, gene_name := attribute(attributes, "gene_name")]
} else {
  feat[, `:=`(id = attribute(attributes, "ID"), parent = attribute(attributes, "Parent"))]
  if (gene_feature == "gene") {
    # Parent links of every feature in the file (a transcript's exons may
    # point to a tRNA or ncRNA feature that is not itself used here).
    # gffread writes transcripts without a Parent and names their gene in
    # geneID instead.
    links <- unique(ann[, .(id = attribute(attributes, "ID"), parent = attribute(attributes, "Parent"),
                            gid = first_of(attribute(attributes, "geneID"), attribute(attributes, "gene_id")))][!is.na(id)],
                    by = "id")
    up <- setNames(links$parent, links$id)
    gid <- setNames(links$gid, links$id)
    root <- feat$parent
    for (hop in 1:5) {
      nxt <- up[root]
      climb <- !is.na(root) & !is.na(nxt)
      if (!any(climb)) break
      root[climb] <- nxt[climb]
    }
    top <- first_of(root, feat$id)
    feat[, gene_id := first_of(unname(gid[top]), top, attribute(attributes, "geneID"), attribute(attributes, "gene_id"))]
  } else {
    feat[, gene_id := first_of(id, attribute(attributes, "gene_id"))]
  }
  feat[, gene_name := first_of(attribute(attributes, "Name"), attribute(attributes, "gene_name"),
                               attribute(attributes, "gene"))]
  # A gene's own Name wins over the names of its transcripts and exons.
  feat[, own := !is.na(id) & id == gene_id]
  feat[, gene_name := c(gene_name[own & !is.na(gene_name)], gene_name[!own & !is.na(gene_name)], NA_character_)[1],
       by = gene_id]
}
feat[is.na(gene_id), gene_id := paste0(contig, ":", start, "-", end)]
from_gene_lines <- feat[type %in% gene_types, uniqueN(gene_id)]
# One row per gene and contig, spanning all its pieces.
genes <- feat[, .(start = min(start), end = max(end), strand = strand[1],
                  gene_name = gene_name[!is.na(gene_name)][1]), by = .(contig, gene_id)]
if (gene_feature == "gene" && nrow(genes) > from_gene_lines)
  message(nrow(genes), " genes: ", from_gene_lines, " from gene lines, ", nrow(genes) - from_gene_lines,
          " rebuilt from transcript/exon/CDS lines without one, each spanning the outermost of its features.")
genes[is.na(gene_name), gene_name := gene_id]
genes <- genes[, .(gene_id, gene_name, contig, start, end, strand)]

off_reference <- genes[!contig %in% contig_order]
if (nrow(off_reference) > 0)
  message(nrow(off_reference), " of ", nrow(genes), " genes lie on contigs that are not in the reference ",
          "(", paste(head(unique(off_reference$contig), 5), collapse = ", "),
          if (uniqueN(off_reference$contig) > 5) ", ..." else "",
          ") and are left out. Check that the annotation's contig names match the reference, ",
          "and whether --min_contig_length removed those contigs.")
genes <- genes[contig %in% contig_order]
if (nrow(genes) == 0)
  stop("No gene in the annotation lies on a contig of the reference: the contig names in ", annotation,
       " do not match those of the reference FASTA.")
order_by_reference(genes, c("start", "end", "gene_id"))
genes[, gene_idx := .I]

# Bins modelled by gCNV (after FilterIntervals) -- the same in every sample.
bins <- read_cnv_vcf(intervals_files[1])[, .(contig, start, end)]
bins[, bin_idx := .I]
setkey(bins, contig, start, end)
gene_bins <- foverlaps(genes[, .(gene_idx, contig, start, end)], bins, nomatch = NULL)[, .(gene_idx, bin_idx)]
genes[, n_bins := 0L]
genes[gene_bins[, .N, by = gene_idx], n_bins := i.N, on = "gene_idx"]

gene_rows <- rbindlist(lapply(seq_along(samples), function(i) {
  s <- samples[i]
  seg <- segments[sample == s, .(contig, seg_start = start, seg_end = end, call, cn, qs)]
  seg[, `:=`(start = seg_start, end = seg_end)]
  setkey(seg, contig, start, end)
  ov <- foverlaps(genes[n_bins > 0, .(gene_idx, contig, start, end)], seg, nomatch = NULL)
  ov[, bp := pmin(i.end, seg_end) - pmax(i.start, seg_start) + 1L]
  per_gene <- ov[, .(
    cn           = cn[which.max(bp)],
    cn_min       = min(cn),
    cn_max       = max(cn),
    frac_altered = sum(bp[call != "REF"]) / (i.end[1] - i.start[1] + 1),
    qs_min       = min(qs)
  ), by = gene_idx]

  ratios <- fread(file.path(paste0(s, ".cnv_denoised_copy_ratios.tsv")), skip = "CONTIG",
                  colClasses = list(character = 1))
  setnames(ratios, c("contig", "start", "end", "ratio"))
  ratios <- ratios[bins, on = .(contig, start, end), .(bin_idx = i.bin_idx, ratio)]
  mean_ratio <- ratios[gene_bins, on = "bin_idx", nomatch = NULL][, .(mean_denoised_cr = mean(ratio)), by = gene_idx]

  out <- data.table(sample = s, gene_idx = genes$gene_idx)
  out <- per_gene[out, on = "gene_idx"]
  out <- mean_ratio[out, on = "gene_idx"]
  out
}))

gene_long <- genes[gene_rows, on = "gene_idx"]
gene_long[, status := fifelse(n_bins == 0 | is.na(cn), "no_bins",
                              fifelse(cn_min == cn_max, "uniform", "breakpoint"))]
gene_long[, filter := fifelse(is.na(qs_min), NA_character_, fifelse(qs_min >= min_qs, "PASS", "LowQual"))]
gene_long[, frac_altered := round(frac_altered, 4)]
gene_long[, mean_denoised_cr := round(mean_denoised_cr, 4)]
setorder(gene_long, gene_idx, sample)
fwrite(gene_long[, .(sample, gene_id, gene_name, contig, start, end, strand, n_bins,
                     cn, cn_min, cn_max, frac_altered, mean_denoised_cr, qs_min, status, filter)],
       "cnv_genes_long.tsv", sep = "\t", na = "NA", quote = FALSE)

gene_matrix <- dcast(gene_long, gene_idx ~ sample, value.var = "cn")
gene_matrix <- genes[, .(gene_idx, gene_id, gene_name, contig, start, end, strand, n_bins)][gene_matrix, on = "gene_idx"]
setorder(gene_matrix, gene_idx)
gene_matrix[, gene_idx := NULL]
fwrite(gene_matrix, "cnv_genes.tsv", sep = "\t", na = "NA", quote = FALSE)
