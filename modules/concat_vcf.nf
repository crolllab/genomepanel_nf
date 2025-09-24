process ConcatVCFs {
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
    bcftools concat $fvcf_ch -Oz > final_variants.vcf.gz
    tabix -p vcf final_variants.vcf.gz
    bcftools query -f '%CHROM,%POS,%QUAL,%AN,%MQ,%DP,%QD\n' final_variants.vcf.gz|gzip > final_variants.metrics.csv.gz
    """
}
