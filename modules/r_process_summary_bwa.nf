process RSummarizingBWA {
  time '1h'
    tag "Summarizing BWA stats"
    cpus 1
    memory '1GB'
  errorStrategy 'retry'
  maxRetries 3
    publishDir "${params.outdir}", mode: 'copy'

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
