process ConcatCleanVCFs {
    tag "BCFtools concat clean VCFs"
    cpus 1
    memory '16GB'
    publishDir params.outdir, mode: 'copy'


    input:
    path clean_vcf_ch
 
    output:
    path "final_variants.clean.vcf.gz*"

    script:

    """   
    bcftools concat ${clean_vcf_ch} -Oz > final_variants.clean.vcf.gz
    """
}
