process samtoolsRealignedIndex {
    time '7d'
    tag "Indexing BAM files"
    errorStrategy 'ignore'
    cpus 1
    memory '4GB'

    input:
    path realigned_bam

    output:
    path "${realigned_bam[0].baseName}.bam.bai"

    script:
    """
    samtools index $realigned_bam
    """
}
