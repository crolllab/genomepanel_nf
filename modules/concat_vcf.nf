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
    # Sort VCF files by chromosome order (natural sort for numeric chromosomes)
    ls filtered.*.vcf.gz | sort -V > vcf_list.txt
    bcftools concat -f vcf_list.txt -Oz > final_variants.vcf.gz
    tabix -p vcf final_variants.vcf.gz
    bcftools query -f '%CHROM,%POS,%QUAL,%AN,%MQ,%DP,%QD\n' final_variants.vcf.gz|gzip > final_variants.metrics.csv.gz
    """
}
