process samtoolsRealignedIndex {
    tag "Indexing BAM files"
    cpus 1
    memory '4GB'
    errorStrategy 'ignore'

    input:
    path realigned_bam

    output:
    path "${realigned_bam[0].baseName}.bam.bai"

    script:
    """
    samtools index $realigned_bam
    """
}
