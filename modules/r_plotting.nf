process RQualPlotting {
    tag "Generating QC report"
    errorStrategy 'retry'
    maxRetries 3
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path concat_vcf
    path fastp_tsv
    path bwa_tsv
    path r_script

    output:
    path "pipeline_report.html", emit: report

    script:
    """
    Rscript ${r_script}
    """
}
