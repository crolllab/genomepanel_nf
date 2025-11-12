process CleanVCFs {
    tag "Remove low-qual SNPs"
    errorStrategy 'ignore'
    cpus 1
    memory '48GB'

    input:
    tuple val(chr), path(fvcf_ch)
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), path("clean.${chr}.vcf.gz")

    script:

    """
    mkdir -p ./gatk_tmp
       
    gatk IndexFeatureFile -I filtered.${chr}.vcf.gz
    gatk --java-options "-Xmx4g" SelectVariants \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V filtered.${chr}.vcf.gz \
        -O clean.${chr}.vcf.gz \
        --exclude-filtered --exclude-non-variants --remove-unused-alternates
    """
}
