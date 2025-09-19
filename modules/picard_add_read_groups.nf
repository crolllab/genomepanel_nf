process addRG {
    tag "PICARD adding ReadGroup in BAM files"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
    
    input:
    tuple val(sample_id), path(sorted_bam), path(sorted_bai)
    
    output:
    tuple val(sample_id), path("${sample_id}_RG.bam"), emit: bam
    
    script:
    """
    picard AddOrReplaceReadGroups \
        -INPUT $sorted_bam \
        -OUTPUT ${sample_id}_RG.bam \
        -RGID ${sample_id} \
        -RGLB ${sample_id}_LB \
        -RGPL ILLUMINA \
        -RGPU unit1 \
        -RGSM ${sample_id} \
        --VALIDATION_STRINGENCY SILENT
    
    # Delete the sorted BAM and BAI files (resolve symlinks to actual files)
    rm "\$(readlink -f "$sorted_bam")"
    rm "\$(readlink -f "$sorted_bai")"
    """
}