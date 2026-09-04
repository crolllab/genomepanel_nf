process mergeRunBAMs {
    tag "Merging runs into sample: ${sample_id}"
    errorStrategy 'retry'
    maxRetries 6

    input:
    tuple val(sample_id), path(bams)

    output:
    tuple val(sample_id), path("${sample_id}_merged.bam"), emit: bam

    script:
    """
    samtools merge -@ ${task.cpus} -f ${sample_id}_merged.bam ${bams}

    # Delete the per-run BAMs now that they are merged (resolve symlinks to the
    # actual files staged by upstream processes).
    for f in ${bams}; do
        target="\$(readlink -f "\$f")"
        [ -n "\$target" ] && [ -f "\$target" ] && rm -f "\$target" || true
    done
    """
}
