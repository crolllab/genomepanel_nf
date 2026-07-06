process dupRemoval {
    tag "PICARD marking duplicates"
    errorStrategy 'retry'
    maxRetries 6

    publishDir "${params.outdir}/bam_files",
        mode: 'copy',
        pattern: "*_RG_dedup.bam*",
        enabled: params.keep_bam

    input:
    tuple val(sample_id), path(rg_bam)

    output:
    tuple val(sample_id),
          path("${sample_id}_RG_dedup.bam"),
          path("${sample_id}_RG_dedup.bam.bai"),
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

    # Delete the RG BAM file (resolve symlink to actual file)
    rg_target="\$(readlink -f "$rg_bam")"
    [ -n "\$rg_target" ] && [ -f "\$rg_target" ] && rm "\$rg_target" || true
    """
}
