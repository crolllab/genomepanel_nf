process GATKHC {
    tag "GATK4 HaplotypeCaller"
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/gvcf_files",
        mode: 'copy',
        pattern: "*.g.vcf.gz*",
        enabled: params.keep_gvcf && (params.reference_segments as Integer) == 0
    
    input:
    path reference
    file "${reference}.fai"
    file "${reference.baseName}.dict"
    file "${reference}.amb"
    file "${reference}.ann"
    file "${reference}.bwt.2bit.64"
    file "${reference}.pac"
    file "${reference}.0123"
    tuple val(sample_id), path(dedup_bam), path(dedup_bai), val(interval), val(chr)
    
    output:
    tuple val(sample_id), val(chr), path("${sample_id}_${interval.replaceAll('[:\\-]', '_')}.g.vcf.gz*")
    
    script:
    """
    set -e  # Exit immediately on error - prevents cleanup if command fails
    
    # Create tmp directory in current location (NXF_SCRATCH, which is bind-mounted)
    mkdir -p ./gatk_tmp
    
    # Create safe filename from interval (replace : and - with _)
    interval_safe=\$(echo "${interval}" | tr ':-' '__')
    
    # Set ERC mode based on invariant sites parameter
    if [ "${params.call_invar_sites}" = "true" ]; then
        ERC_MODE="BP_RESOLUTION"
    else
        ERC_MODE="GVCF"
    fi
    
    gatk --java-options "-Xmx${task.memory.toGiga()-2}g -XX:-UsePerfData --enable-native-access=ALL-UNNAMED" HaplotypeCaller \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -L "${interval}" \
        --sample-ploidy $params.ploidy \
        -input ${dedup_bam} \
        -output ${sample_id}_\${interval_safe}.g.vcf.gz \
        -ERC \${ERC_MODE} \
        --create-output-variant-index

    # BAM cleanup is handled by the cleanupBAMs process in the workflow,
    # which runs only after ALL GATKHC tasks across every interval complete.
    """
}
