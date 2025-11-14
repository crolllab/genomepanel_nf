process GenotypeGVCFs {
    tag "GATK4 Genotype GVCFs"
    cpus 1
    memory { 16.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 2


    input:
    tuple val(chr), path(cgvcf)
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), path("genotyped.${chr}.vcf.gz")

    script:
    """
    mkdir -p ./gatk_tmp
       
    gatk IndexFeatureFile -I combined.${chr}.g.vcf.gz
    gatk --java-options "-Xmx16g" GenotypeGVCFs \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V combined.${chr}.g.vcf.gz \
        -output genotyped.${chr}.vcf.gz
    
    # Delete the combined GVCF (resolve symlink to actual file)
    cgvcf_target="\$(readlink -f "combined.${chr}.g.vcf.gz")"
    [ -n "\$cgvcf_target" ] && [ -f "\$cgvcf_target" ] && rm "\$cgvcf_target" || true
    """
}
