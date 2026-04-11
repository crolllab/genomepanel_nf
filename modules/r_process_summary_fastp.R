library(jsonlite)

# Keys from summary.before_filtering / summary.after_filtering (appear twice,
# once for each section; duplicate row names are intentional so that
# r_plotting.R can call get_row(key, n=1) for before and get_row(key, n=2)
# for after).
SUMMARY_KEYS <- c("total_reads", "total_bases", "q20_bases", "q30_bases",
                  "q20_rate", "q30_rate", "read1_mean_length",
                  "read2_mean_length", "gc_content")

# Keys from filtering_result (appear once)
FILTER_KEYS <- c("passed_filter_reads", "low_quality_reads",
                 "too_many_N_reads", "too_short_reads", "too_long_reads")

files <- list.files(pattern = "_(PE|SE)_fastp.json$")
if (length(files) == 0) quit(save = "no", status = 0)

samples <- sub("_(PE|SE)_fastp.json$", "", files)

# Row layout: before_filtering keys, then after_filtering keys (same names),
# then filtering_result keys, then duplication_rate and insert_size_peak.
row_names <- c(SUMMARY_KEYS, SUMMARY_KEYS, FILTER_KEYS,
               "duplication_rate", "insert_size_peak")

mat <- matrix(NA_real_, nrow = length(row_names), ncol = length(files),
              dimnames = list(row_names, samples))

n_sum    <- length(SUMMARY_KEYS)
n_filter <- length(FILTER_KEYS)

for (i in seq_along(files)) {
  j  <- fromJSON(files[[i]], simplifyVector = TRUE)
  bf <- j$summary$before_filtering
  af <- j$summary$after_filtering
  fr <- j$filtering_result

  for (k in seq_along(SUMMARY_KEYS)) {
    key <- SUMMARY_KEYS[[k]]
    mat[k,          i] <- if (!is.null(bf[[key]])) as.numeric(bf[[key]]) else NA_real_
    mat[k + n_sum,  i] <- if (!is.null(af[[key]])) as.numeric(af[[key]]) else NA_real_
  }
  for (k in seq_along(FILTER_KEYS)) {
    key <- FILTER_KEYS[[k]]
    mat[2*n_sum + k, i] <- if (!is.null(fr[[key]])) as.numeric(fr[[key]]) else NA_real_
  }
  base <- 2*n_sum + n_filter
  mat[base + 1, i] <- tryCatch(as.numeric(j$duplication$rate), error = function(e) NA_real_)
  mat[base + 2, i] <- tryCatch(as.numeric(j$insert_size$peak),  error = function(e) NA_real_)
}

write.table(mat, file = "fastp_summary.tsv", sep = "\t", quote = FALSE, col.names = NA)
