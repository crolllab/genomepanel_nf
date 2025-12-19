process addRG {
    tag "PICARD adding ReadGroup in BAM files"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
       
    input:
    tuple val(sample_id), path(sorted_bam), path(sorted_bai)
    path sample_map
    
    output:
    tuple val(sample_id), path("${sample_id}_RG.bam"), emit: bam
    
    script:
    // Determine the sample name (SM tag) - either from map file or use original sample_id
    // The sample_map file format: SRR_ID,Sample_Name (CSV, no header)
    // Note: sample_id is kept for file naming; RG_SAMPLE is used for the SM tag in BAM
    // GATK CombineGVCFs will merge GVCFs with the same SM tag into a single sample
    """
    # Check if sample map file exists, is not a placeholder, and is not empty
    if [ -f "${sample_map}" ] && [ -s "${sample_map}" ] && [ "${sample_map}" != "NO_SAMPLE_MAP.txt" ]; then
        # Look up sample name from map file (format: SRR_ID,Sample_Name)
        # Use head -1 to handle potential duplicate entries (first match wins)
        MAPPED_SAMPLE=\$(grep "^${sample_id}," "${sample_map}" | head -1 | cut -d',' -f2 | tr -d '\\r\\n' || true)
        if [ -n "\$MAPPED_SAMPLE" ]; then
            RG_SAMPLE="\$MAPPED_SAMPLE"
            echo "Mapped ${sample_id} to sample name: \$RG_SAMPLE"
        else
            RG_SAMPLE="${sample_id}"
            echo "No mapping found for ${sample_id}, using original ID"
        fi
    else
        RG_SAMPLE="${sample_id}"
        echo "No sample map provided, using original ID: ${sample_id}"
    fi
    
    picard AddOrReplaceReadGroups \
        -INPUT $sorted_bam \
        -OUTPUT ${sample_id}_RG.bam \
        -RGID ${sample_id} \
        -RGLB \${RG_SAMPLE}_LB \
        -RGPL ILLUMINA \
        -RGPU unit1 \
        -RGSM \${RG_SAMPLE} \
        --VALIDATION_STRINGENCY SILENT
    
    # Delete the sorted BAM and BAI files (resolve symlinks to actual files)
    bam_target="\$(readlink -f "$sorted_bam")"
    bai_target="\$(readlink -f "$sorted_bai")"
    [ -n "\$bam_target" ] && [ -f "\$bam_target" ] && rm "\$bam_target" || true
    [ -n "\$bai_target" ] && [ -f "\$bai_target" ] && rm "\$bai_target" || true
    """
}