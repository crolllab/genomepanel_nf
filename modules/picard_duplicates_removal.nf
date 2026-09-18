process dupRemoval {
    tag "PICARD marking duplicates"
    errorStrategy { task.attempt <= 6 ? 'retry' : 'ignore' }
    maxRetries 6

    publishDir "${params.outdir}/5_bam_files",
        mode: 'copy',
        pattern: "*_RG_dedup.bam*",
        enabled: params.keep_bam

    input:
    // consumed: the read-group (or merged) BAM, deleted by the workflow once
    // this task's output is accepted (see modules/delete_intermediates.nf)
    tuple val(sample_id), path(rg_bam), val(consumed)

    output:
    tuple val(sample_id),
          path("${sample_id}_RG_dedup.bam"),
          path("${sample_id}_RG_dedup.bam.bai"),
          val(consumed),
          emit: bam

    script:
    """
    picard -Xmx${task.memory.toGiga()-2}g MarkDuplicates \
        -INPUT $rg_bam \
        -OUTPUT ${sample_id}_RG_dedup.bam \
        -METRICS_FILE ${sample_id}_DUP_metrics.txt \
        -REMOVE_DUPLICATES false \
        --VALIDATION_STRINGENCY SILENT

    picard -Xmx${task.memory.toGiga()-2}g BuildBamIndex \
        -INPUT ${sample_id}_RG_dedup.bam \
        -OUTPUT ${sample_id}_RG_dedup.bam.bai
    """
}
