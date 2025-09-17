process dupRemoval {
    tag "PICARD marking duplicates in BAM files for $sample_id"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
    
    input:
    tuple val(sample_id), path(rg_bam)
    
    output:
    tuple val(sample_id), path("${sample_id}_RG_dedup.bam"), path("${sample_id}_RG_dedup.bam.bai"), emit: bam
    
    script:
    """
    picard MarkDuplicates \
        -INPUT $rg_bam \
        -OUTPUT ${sample_id}_RG_dedup.bam \
        -METRICS_FILE ${sample_id}_DUP_metrics.txt \
        -REMOVE_DUPLICATES true \
        --VALIDATION_STRINGENCY SILENT
    
    picard BuildBamIndex \
        -INPUT ${sample_id}_RG_dedup.bam \
        -OUTPUT ${sample_id}_RG_dedup.bam.bai
    """
}