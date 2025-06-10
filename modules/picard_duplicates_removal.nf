process dupRemoval {
    tag "PICARD marking duplicates in BAM files"
    cpus 1
    memory '16GB'
    errorStrategy 'ignore'

    input:
    path rg_bam

    output:
    path "${rg_bam[0].baseName}_dedup.bam"

    script:
    """
    picard MarkDuplicates -INPUT $rg_bam -OUTPUT ${rg_bam[0].baseName}_dedup.bam -METRICS_FILE ${rg_bam[0].baseName}_DUP_metrics.txt -REMOVE_DUPLICATES true --VALIDATION_STRINGENCY SILENT
    """
}
