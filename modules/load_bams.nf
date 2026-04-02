process loadBAMs {
    time '1h'
    cpus 1
    memory '1GB'
    errorStrategy 'retry'
    maxRetries 3
    tag "Loading pre-existing BAM files"
    
    input:
    tuple val(sample_id), path(bam), path(bai)

    output:
    tuple val(sample_id),
          path(bam),
          path(bai),
          emit: bam

    script:
    """
    # No processing needed - just passing through validated BAM files
    echo "Loaded BAM file for sample: ${sample_id}"
    """
}
