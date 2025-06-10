process GenotypeGVCFs {
    tag "GATK4 Genotype GVCFs"
    cpus 1
    time '72h'

    input:
    path cgvcf
    val chr
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    path "genotyped.*.vcf.gz"

    script:
    """   
        gatk IndexFeatureFile -I combined.${chr}.g.vcf.gz
        gatk --java-options "-Xmx4g" GenotypeGVCFs -R $reference -V combined.${chr}.g.vcf.gz -output genotyped.${chr}.vcf.gz
    """
}
