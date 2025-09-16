process RSummarizingBWA {
    tag "Summarizing BWA step with R"
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path json_files

    output:
    path "bwa_summary.tsv"

    script:
    """
    cat > summarize.R << 'EOF'
    # Collect input files
    files <- list.files(pattern = "_flagstat.json\$")

    data_list <- list()

    for (f in files) {
      txt <- readLines(f, warn=FALSE)
      txt <- paste(txt, collapse='')
      txt <- gsub('[{}"]', '', txt)

      kv <- unlist(strsplit(txt, ','))
      flat <- numeric(0)
      names_vec <- character(0)

      for (pair in kv) {
        parts <- unlist(strsplit(pair, ':'))
        key <- trimws(parts[1])
        value <- as.numeric(trimws(parts[2]))
        if (is.na(value)) value <- 0
        flat <- c(flat, value)
        names_vec <- c(names_vec, key)
      }

      data_list[[f]] <- flat
      names(data_list[[f]]) <- names_vec
    }

    max_rows <- max(sapply(data_list, length))
    for (i in seq_along(data_list)) {
      length(data_list[[i]]) <- max_rows
    }

    df <- do.call(cbind, data_list)
    rownames(df) <- names(data_list[[1]])
    colnames(df) <- sub('_flagstat.json', '', files)

    write.table(df, file='bwa_summary.tsv', sep="\\t", quote=FALSE, col.names=NA)
    EOF

    Rscript summarize.R
    """
}