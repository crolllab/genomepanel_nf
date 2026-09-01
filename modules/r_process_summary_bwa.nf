process RSummarizingBWA {
    tag "Summarizing BWA stats"
  errorStrategy 'retry'
  maxRetries 6
    publishDir "${params.outdir}/4_bwa_mapping", mode: 'copy'

    input:
    path json_files
    path r_script

    output:
    path "bwa_summary.tsv"

    script:
    """
    Rscript ${r_script}
    """
}
