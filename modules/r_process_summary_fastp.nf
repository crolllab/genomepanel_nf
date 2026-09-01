process RSummarizingFASTP {
    tag "Summarizing FASTP stats"
  errorStrategy 'retry'
  maxRetries 6
    publishDir "${params.outdir}/3_fastq_stats", mode: 'copy'


    input:
    path json_files
    path r_script

    output:
    path "fastp_summary.tsv"

    script:
    """
    Rscript ${r_script}
    """
}
