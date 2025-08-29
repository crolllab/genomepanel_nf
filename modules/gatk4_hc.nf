process GATKHC {
    tag "GATK4 HaplotypeCaller"
    errorStrategy 'ignore'
    cpus 1
    memory '20GB'

    input:
    path reference
    file "${reference.baseName}.fasta.fai"
    file "${reference.baseName}.dict"
    file "${reference.baseName}.fasta.amb"

    file "${rg_bam[0].baseName}_dedup.bam"
    file "${rg_bam[0].baseName}_dedup.bam.bai"

    output:
    path "${dedup_bam[0].baseName}.g.vcf.gz*"

    script:
    """
    gatk --java-options "-Xmx4g" HaplotypeCaller -R $reference --sample-ploidy $params.ploidy -input ${rg_bam[0].baseName}_dedup.bam -output ${dedup_bam[0].baseName}.g.vcf.gz -ERC GVCF --create-output-variant-index
    """
}
