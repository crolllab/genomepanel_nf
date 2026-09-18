process cleanupBAMs {
    tag "Cleanup BAMs: ${sample_id}"
    // Housekeeping only: every variant call is already made when this runs, so
    // a failed delete must not abort the run. The file is left behind instead.
    errorStrategy 'ignore'

    input:
    tuple val(sample_id), path(bam), path(bai)
    val gatkhc_done   // sentinel: count of completed GATKHC tasks; only available after ALL tasks finish

    script:
    """
    # Resolve symlinks staged by Nextflow back to the real files in the dupRemoval work dir
    bam_real="\$(readlink -f "${bam}")"
    bai_real="\$(readlink -f "${bai}")"
    [ -f "\$bam_real" ] && rm -f "\$bam_real" || true
    [ -f "\$bai_real" ] && rm -f "\$bai_real" || true
    echo "Deleted BAM/BAI for ${sample_id} (${gatkhc_done} GATKHC tasks completed)"
    """
}
