process GenotypeGVCFs {
    tag "GATK4 Genotype GVCFs"
    errorStrategy 'ignore'
    cpus 1
    memory '48GB'

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
    gatk --java-options "-Xmx48g" GenotypeGVCFs -R $reference -V combined.${chr}.g.vcf.gz -output genotyped.${chr}.vcf.gz
    rm "\$(readlink -f "combined.${chr}.g.vcf.gz")"
    """
}
