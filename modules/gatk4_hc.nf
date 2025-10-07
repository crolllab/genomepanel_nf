process GATKHC {
    tag "GATK4 HaplotypeCaller"
    errorStrategy 'ignore'
    cpus 1
    memory '8GB'
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
    gatk --java-options "-Xmx8g" HaplotypeCaller \
        -R $reference \
        --sample-ploidy $params.ploidy \
        -input ${dedup_bam} \
        -output ${sample_id}.g.vcf.gz \
        -ERC GVCF \
        --create-output-variant-index
    
    # Safe cleanup - handle concurrent deletion gracefully
    bam_target="\$(readlink -f "$dedup_bam")"
    bai_target="\$(readlink -f "$dedup_bai")"
    [ -n "\$bam_target" ] && [ -f "\$bam_target" ] && rm "\$bam_target" || true
    [ -n "\$bai_target" ] && [ -f "\$bai_target" ] && rm "\$bai_target" || true
    """
}