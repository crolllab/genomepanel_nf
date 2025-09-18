process PopGenVCF {
    tag "Generating VCF for pop. gen."
    cpus 1
    memory '4GB'
    errorStrategy 'ignore'
    publishDir params.outdir, mode: 'copy'

    input:
    path concat_clean_vcf

    output:
    path "${concat_clean_vcf.baseName}_thin1000_maf0.05_maxm0.9.recode.vcf.gz"


    script:
    """
    vcftools \
        --gzvcf $concat_clean_vcf \
        --thin 1000 \
        --max-missing 0.9 \
        --maf 0.05 \
        --recode \
        --recode -c | gzip -c > ${concat_clean_vcf.baseName}_thin1000_maf0.05_maxm0.9.recode.vcf.gz
    """
}
