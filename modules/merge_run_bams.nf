process mergeRunBAMs {
    tag "Merging runs into sample: ${sample_id}"
    errorStrategy { task.attempt <= 3 ? 'retry' : 'ignore' }
    maxRetries 3

    input:
    // consumed: the per-run BAMs, deleted by the workflow once this task's
    // output is accepted (see modules/delete_intermediates.nf). Empty for
    // --bam_input, whose BAMs belong to the user.
    tuple val(sample_id), path(bams), val(consumed)

    output:
    tuple val(sample_id), path("${sample_id}_merged.bam"), val(consumed), emit: bam

    script:
    """
    samtools merge -@ ${task.cpus} -f ${sample_id}_merged.bam ${bams}
    """
}
