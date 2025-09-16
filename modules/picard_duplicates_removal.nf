process dupRemoval {
    tag "PICARD marking duplicates in BAM files"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'

    input:
    path rg_bam

    output:
    tuple path("${rg_bam[0].baseName}_dedup.bam"), path("${rg_bam[0].baseName}_dedup.bam.bai")

    script:
    """
    picard MarkDuplicates -INPUT $rg_bam -OUTPUT ${rg_bam[0].baseName}_dedup.bam -METRICS_FILE ${rg_bam[0].baseName}_DUP_metrics.txt -REMOVE_DUPLICATES true --VALIDATION_STRINGENCY SILENT
    picard BuildBamIndex -INPUT ${rg_bam[0].baseName}_dedup.bam -OUTPUT ${rg_bam[0].baseName}_dedup.bam.bai
    #rm "\$(readlink -f "$rg_bam")"
    """
}
