process SRAdownload {
    tag "$sra_id"
    maxForks params.max_concurrent ?: 10
    errorStrategy 'retry'
    maxRetries 2

    input:
    val sra_id

    output:
    tuple val(sra_id), path("${sra_id}_*.fastq")

    script:
    """
    set -euo pipefail

    echo "Downloading and converting $sra_id"

    # First attempt
    fasterq-dump $sra_id --split-files --outdir . || {

        echo "First attempt failed, retrying with --legacy"
        # Retry with --legacy option
        fasterq-dump $sra_id --split-files --outdir . --legacy || {

            echo "Download failed for $sra_id after retry"
            exit 1
        }
    }

    echo "$sra_id download and conversion complete"
    """
}
