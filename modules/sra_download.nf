process SRAdownload {
    tag "$sra_id"
    maxForks params.max_concurrent
    errorStrategy 'retry'
    maxRetries 2

    input:
    val sra_id

    output:
    tuple val(sra_id), path("${sra_id}_*.fastq")

    script:
    """
    set -euo pipefail

    # Check if files already exist
    if ls ${sra_id}_*.fastq 1>/dev/null 2>&1; then
        echo "Skipping $sra_id, FASTQ files already exist"
    else
        echo "Downloading and converting $sra_id"
        fasterq-dump $sra_id --split-files --outdir .
        echo "$sra_id download and conversion complete"
    fi
    """
}

