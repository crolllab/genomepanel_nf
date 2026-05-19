process MergeGVCFs {
    tag "Merge GVCFs: ${sample_id}"
    errorStrategy 'retry'
    maxRetries 3
    publishDir "${params.outdir}/gvcf_files",
        mode: 'copy',
        pattern: "*.g.vcf.gz*"

    input:
    tuple val(sample_id), path(gvcf_files)

    output:
    tuple val(sample_id), path("${sample_id}.g.vcf.gz"), path("${sample_id}.g.vcf.gz.tbi")

    script:
    """
    # List all segmented GVCF files and sort by natural chromosome/position order
    ls *.g.vcf.gz | sort -V > gvcf_list.txt

    # Concatenate all segments into a single per-sample GVCF
    bcftools concat -a -D -f gvcf_list.txt -Oz -o ${sample_id}.g.vcf.gz

    # Index the merged GVCF
    tabix -p vcf ${sample_id}.g.vcf.gz
    """
}
