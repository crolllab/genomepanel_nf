process SRAdownload {
    tag "$sra_id"
    maxForks params.max_concurrent ?: 4
    errorStrategy 'retry'
    maxRetries 2

    input:
    val sra_id    // <-- plain string SRR

    output:
    tuple val(sra_id), path("${sra_id}_*.fastq")

    script:
    """
    set -euo pipefail

    # Skip if FASTQs already exist
    if ls ${sra_id}_*.fastq 1>/dev/null 2>&1; then
        echo "$sra_id FASTQs already exist, skipping"
    else
        echo "Downloading $sra_id..."
        fasterq-dump $sra_id --split-files --outdir .
    fi
    """
}