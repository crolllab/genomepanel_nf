// Simplified processes for PE and SE downloads with basic failure tracking
process SRAdownloadPE {
    cpus 1
    memory '4GB'
    tag "Downloading $srr from NCBI SRA"
    errorStrategy 'ignore'
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}_*.fastq"), optional: true
    path "failed_${srr}.txt", optional: true
    
    script:
    """
    # Try to download the files
    if fasterq-dump $srr --split-files -O . 1>/dev/null 2>&1; then
        # Success - no failure file needed
        echo "Download successful for $srr"
    else
        echo "ERROR: fasterq-dump failed for $srr" >&2
        echo -e "$srr\tPE\tfasterq-dump failed" > failed_${srr}.txt
        # Create dummy output files to satisfy the tuple output
        touch ${srr}_1.fastq
        exit 1
    fi
    """
}

process SRAdownloadSE {
    cpus 1
    memory '4GB'
    tag "Downloading $srr from NCBI SRA"
    errorStrategy 'ignore'
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}_*.fastq"), optional: true
    path "failed_${srr}.txt", optional: true
    
    script:
    """
    # Try to download the file
    if fasterq-dump $srr --split-files -O . 1>/dev/null 2>&1; then
        # Success - no failure file needed
        echo "Download successful for $srr"
    else
        echo "ERROR: fasterq-dump failed for $srr" >&2
        echo -e "$srr\tSE\tfasterq-dump failed" > failed_${srr}.txt
        # Create dummy output file to satisfy the tuple output
        touch ${srr}.fastq
        exit 1
    fi
    """
}

// Process to collect all failure reports
process CollectFailedDownloads {
    tag "Collecting failed download reports"
    publishDir "${params.outdir}", mode: 'copy'
    
    input:
    path failed_files
    
    output:
    path "NCBI_failed_downloads.tsv"
    
    script:
    """
    echo -e "SRR_ID\tType\tError_Reason" > NCBI_failed_downloads.tsv
    
    # Check if we have any failure files
    if ls failed_*.txt 1> /dev/null 2>&1; then
        cat failed_*.txt >> NCBI_failed_downloads.tsv
    else
        echo -e "# No failed downloads" >> NCBI_failed_downloads.tsv
    fi
    """
}