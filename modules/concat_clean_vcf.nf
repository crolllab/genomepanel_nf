process ConcatCleanVCFs {
    tag "BCFtools concat clean VCFs"
    cpus 1
    memory '48GB'
    publishDir params.outdir, mode: 'copy'

    input:
    path clean_vcf_ch
 
    output:
    path "final_variants.clean.vcf.gz*"

    script:

    """
    # Sort VCF files by chromosome order (natural sort for numeric chromosomes)
    ls clean.*.vcf.gz | sort -V > vcf_list.txt
    bcftools concat -f vcf_list.txt -Oz > final_variants.clean.vcf.gz
    """
}
