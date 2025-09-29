process GATKHC {
    tag "GATK4 HaplotypeCaller"
    errorStrategy 'retry'
    maxRetries 3
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
    # Run GATK HaplotypeCaller
    gatk --java-options "-Xmx8g" HaplotypeCaller \
        -R $reference \
        --sample-ploidy $params.ploidy \
        -input ${dedup_bam} \
        -output ${sample_id}.g.vcf.gz \
        -ERC GVCF \
        --create-output-variant-index
    
    # Only delete files if GATK completed successfully
    if [ \$? -eq 0 ]; then
        echo "GATK HaplotypeCaller completed successfully for ${sample_id}, cleaning up input files"
        rm "\$(readlink -f "$dedup_bam")" 2>/dev/null || echo "Could not delete $dedup_bam"
        rm "\$(readlink -f "$dedup_bai")" 2>/dev/null || echo "Could not delete $dedup_bai"
    else
        echo "GATK HaplotypeCaller failed for ${sample_id}, preserving input files"
        exit 1
    fi
    """
}