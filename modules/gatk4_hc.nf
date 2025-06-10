process GATKHC {
    tag "GATK4 HaplotypeCaller"
    cpus 1
    memory '20GB'
    maxRetries 2
    errorStrategy = { (task.attempt <= process.maxRetries) ? 'retry' : 'ignore' }

    input:
    path reference
    file "${reference.baseName}.fasta.fai"
    file "${reference.baseName}.dict"
    path dedup_bam
    path dedup_bai

    output:
    path "${dedup_bam[0].baseName}.g.vcf.gz*"

    script:
    """
    gatk --java-options "-Xmx4g" HaplotypeCaller -R $reference --sample-ploidy $params.ploidy -input $dedup_bam -output ${dedup_bam[0].baseName}.g.vcf.gz -ERC GVCF --create-output-variant-index
    """
}
