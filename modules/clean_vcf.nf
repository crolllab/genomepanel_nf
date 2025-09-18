process CleanVCFs {
    tag "Remove low-qual SNPs"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'

    input:
    path fvcf_ch
    val chr
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    path "clean.*.vcf.gz"

    script:

    """   
    gatk IndexFeatureFile -I filtered.${chr}.vcf.gz
    gatk --java-options "-Xmx4g" SelectVariants -R $reference -V filtered.${chr}.vcf.gz  -O clean.${chr}.vcf.gz --exclude-filtered --exclude-non-variants --remove-unused-alternates
    """
}
