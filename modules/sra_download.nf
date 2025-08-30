process downloadSRA {
    tag "$sra_id"
    maxForks { params.max_concurrent ?: 10 }  // limit concurrency (default 10)

    input:
    val sra_id from sra_ids_ch

    output:
    file("${sra_id}*.fastq") into read_pairs_ch

    script:
    """
    prefetch $sra_id --api-key $params.NCBI_api_key --protocol ftp
    fasterq-dump $sra_id --split-files --outdir .
    """
}
