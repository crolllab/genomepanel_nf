process GATKHC {
    tag "GATK4 HaplotypeCaller"
    cpus 1
    memory { 8.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 3
    publishDir "${params.outdir}/gvcf_files",
        mode: 'copy',
        pattern: "*.g.vcf.gz*",
        enabled: params.keep_gvcf
    
    input:
    path reference
    file "${reference.baseName}.fasta.fai"
    file "${reference.baseName}.dict"
    file "${reference.baseName}.fasta.amb"
    file "${reference.baseName}.fasta.ann"
    file "${reference.baseName}.fasta.bwt.2bit.64"
    file "${reference.baseName}.fasta.pac"
    file "${reference.baseName}.fasta.0123"
    tuple val(sample_id), path(dedup_bam), path(dedup_bai), val(interval), val(chr)
    
    output:
    tuple val(chr), path("${sample_id}_${interval.replaceAll('[:\\-]', '_')}.g.vcf.gz*")
    
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
    
    gatk --java-options "-Xmx${task.memory.toGiga()-2}g" HaplotypeCaller \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -L "${interval}" \
        --sample-ploidy $params.ploidy \
        -input ${dedup_bam} \
        -output ${sample_id}_\${interval_safe}.g.vcf.gz \
        -ERC \${ERC_MODE} \
        --create-output-variant-index
    
    # NOTE: Do NOT delete BAM files here!
    # When processing by chromosome, the same BAM is used by multiple GATKHC tasks.
    # Nextflow will handle cleanup automatically after all tasks using the BAM complete.
    """
}