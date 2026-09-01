process ConcatCleanVCFs {
    tag "BCFtools concat clean VCFs"
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/7_variants", mode: 'copy'

    input:
    path clean_vcf_ch
 
    output:
    path "final_variants.clean.vcf.gz*"

    script:

    """
    # Sort VCF files by chromosome and position order (natural sort handles chr names and positions)
    ls clean.*.vcf.gz | sort -V > vcf_list.txt
    
    # Concatenate with -a (allow overlaps) and -D (remove duplicates at boundaries)
    # This handles adjacent 1 Mb segments that might have variants at boundaries
    bcftools concat -a -D -f vcf_list.txt -Oz > final_variants.clean.vcf.gz
    tabix -p vcf final_variants.clean.vcf.gz
    """
}
