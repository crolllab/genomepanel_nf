process GATKHC {
    tag "GATK4 HaplotypeCaller"
    cpus 1
    memory '8GB'
    maxForks 15  // Limit concurrency to reduce NFS load
    errorStrategy { sleep(120 * 60 * 1000); return 'retry' }
    maxRetries 3
    publishDir "${params.outdir}/gvcf_files",
        mode: 'copy',
        pattern: "*.g.vcf.gz*",
        enabled: params.keep_bam_gvcf
    
    input:
    path reference
    file "${reference.baseName}.fasta.fai"
    file "${reference.baseName}.dict"
    file "${reference.baseName}.fasta.amb"
    file "${reference.baseName}.fasta.ann"
    file "${reference.baseName}.fasta.bwt.2bit.64"
    file "${reference.baseName}.fasta.pac"
    file "${reference.baseName}.fasta.0123"
    tuple val(sample_id), path(dedup_bam), path(dedup_bai)
    
    output:
    path "${sample_id}.g.vcf.gz*"
    
    script:
    """
    set -e  # Exit immediately on error - prevents cleanup if command fails
    
    # Create tmp directory in current location (NXF_SCRATCH, which is bind-mounted)
    mkdir -p ./gatk_tmp
    
    gatk --java-options "-Xmx8g" HaplotypeCaller \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        --sample-ploidy $params.ploidy \
        -input ${dedup_bam} \
        -output ${sample_id}.g.vcf.gz \
        -ERC GVCF \
        --create-output-variant-index
    
    # Only reached if GATK succeeded - cleanup input files
    bam_target="\$(readlink -f "$dedup_bam")"
    bai_target="\$(readlink -f "$dedup_bai")"
    [ -n "\$bam_target" ] && [ -f "\$bam_target" ] && rm "\$bam_target" || true
    [ -n "\$bai_target" ] && [ -f "\$bai_target" ] && rm "\$bai_target" || true
    """
}