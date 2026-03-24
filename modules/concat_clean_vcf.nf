process ConcatCleanVCFs {
    time '7d'
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
    # Sort VCF files by chromosome and position order (natural sort handles chr names and positions)
    ls clean.*.vcf.gz | sort -V > vcf_list.txt
    
    # Concatenate with -a (allow overlaps) and -D (remove duplicates at boundaries)
    # This handles adjacent 1 Mb segments that might have variants at boundaries
    bcftools concat -a -D -f vcf_list.txt -Oz > final_variants.clean.vcf.gz
    tabix -p vcf final_variants.clean.vcf.gz
    """
}
