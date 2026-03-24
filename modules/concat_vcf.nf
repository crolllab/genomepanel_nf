process ConcatVCFs {
    time '7d'
    tag "BCFtools concat VCFs + qual metrics"
    cpus 1
    memory '48GB'
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path fvcf_ch
 
    output:
    path "final_variants.*"

    script:

    """
    # Sort VCF files by chromosome and position order (natural sort handles chr names and positions)
    ls filtered.*.vcf.gz | sort -V > vcf_list.txt
    
    # Concatenate with -a (allow overlaps) and -D (remove duplicates at boundaries)
    # This handles adjacent 1 Mb segments that might have variants at boundaries
    bcftools concat -a -D -f vcf_list.txt -Oz > final_variants.vcf.gz
    tabix -p vcf final_variants.vcf.gz
    bcftools query -f '%CHROM,%POS,%QUAL,%AN,%MQ,%DP,%QD\n' final_variants.vcf.gz|gzip > final_variants.metrics.csv.gz
    """
}
