process RQualPlotting {
    tag "Generating QC report"
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/10_reports", mode: 'copy'

    input:
    path concat_vcf
    path fastp_tsv
    path bwa_tsv
    path ignored_samples
    path r_script
    val  pipeline_version
    val  pipeline_start

    output:
    path "pipeline_report.html", emit: report

    script:
    """
    echo -e "version\t${pipeline_version}" > pipeline_meta.txt
    echo -e "report_date\t\$(date '+%Y-%m-%d %H:%M')" >> pipeline_meta.txt
    echo -e "pipeline_start\t${pipeline_start}" >> pipeline_meta.txt
    Rscript ${r_script}
    """
}
