process PopGenVCF {
    tag "Generating VCF for pop. gen."
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/8_popgen_vcf", mode: 'copy'

    input:
    path vcf_files

    output:
    path "final_variants.clean.vcf_thin1000_maf0.05_maxm0.9.recode.vcf.gz"


    script:
    """
    # Find the VCF file (not the index)
    vcf_file=\$(ls *.vcf.gz | grep -v '.tbi' | head -1)
    
    vcftools \
        --gzvcf \${vcf_file} \
        --thin 1000 \
        --max-missing 0.9 \
        --maf 0.05 \
        --recode \
        --stdout | gzip -c > final_variants.clean.vcf_thin1000_maf0.05_maxm0.9.recode.vcf.gz
    """
}
