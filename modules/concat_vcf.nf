process ConcatVCFs {
    tag "BCFtools concat VCFs + qual metrics"
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/7_variants", mode: 'copy'

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
    TOTAL=\$(bcftools view -H final_variants.vcf.gz | wc -l)
    FRAC=\$(awk -v t="\$TOTAL" 'BEGIN{ printf "%.6f", (t <= 1000 ? 1.0 : 1000/t) }')
    bcftools query -f '%CHROM,%POS,%QUAL,%AN,%MQ,%DP,%QD\n' final_variants.vcf.gz \
        | awk -v frac="\$FRAC" 'BEGIN{srand(42)} (frac >= 1.0 || rand() < frac)' \
        | gzip > final_variants.metrics.csv.gz

    # Variant summary counts (SNPs / indels, all vs PASS)
    TOTAL_SNPS=\$(bcftools view -H --type snps   final_variants.vcf.gz | wc -l)
    TOTAL_INDELS=\$(bcftools view -H --type indels final_variants.vcf.gz | wc -l)
    PASS_SNPS=\$(bcftools view -H -f PASS --type snps   final_variants.vcf.gz | wc -l)
    PASS_INDELS=\$(bcftools view -H -f PASS --type indels final_variants.vcf.gz | wc -l)
    printf 'category\tcount\n'             > final_variants.variant_stats.tsv
    printf 'Total SNPs\t%s\n'   "\$TOTAL_SNPS"   >> final_variants.variant_stats.tsv
    printf 'Total indels\t%s\n' "\$TOTAL_INDELS" >> final_variants.variant_stats.tsv
    printf 'PASS SNPs\t%s\n'    "\$PASS_SNPS"    >> final_variants.variant_stats.tsv
    printf 'PASS indels\t%s\n'  "\$PASS_INDELS"  >> final_variants.variant_stats.tsv
    """
}
