process SRAdownload {
    tag "$sra_id"
    maxForks params.max_concurrent ?: 10

    input:
    val sra_id

    output:
    tuple val(sra_id), path("${sra_id}_*.fastq")

    script:
    """
    fasterq-dump $sra_id --split-files --outdir . --legacy
    """
}
