// Simple SRA download process using prefetch, then fasterq-dump
process SRAdownloadPE {
    cpus 1
    memory '4GB'
    tag "Downloading $srr from NCBI SRA"
    errorStrategy 'retry'
    maxRetries 3
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}_*.fastq"), optional: true
    path "failed_${srr}.txt", optional: true
    
    script:
    """
    # Function to attempt download with prefetch + fasterq-dump
    attempt_download() {
        local attempt=\$1
        echo "Attempt \$attempt: Downloading $srr with prefetch"
        
        # Clean up any partial files from previous attempts
        rm -f ${srr}_*.fastq
        rm -rf ${srr}/
        rm -f ${srr}.sra
        
        # Step 1: Use prefetch
        echo "Step 1: Using prefetch for $srr"
        if prefetch  $srr 1>/dev/null 2>error.log; then
            echo "Prefetch successful for $srr"
            
            # Step 2: Convert SRA to FASTQ using fasterq-dump
            echo "Step 2: Converting SRA to FASTQ for $srr"
            if fasterq-dump $srr --split-files -O . 1>/dev/null 2>>error.log; then
                # Check if we actually got files
                if ls ${srr}_*.fastq 1> /dev/null 2>&1; then
                    echo "Complete download successful for $srr on attempt \$attempt"
                    # Clean up SRA file to save space
                    rm -rf ${srr}/
                    rm -f ${srr}.sra
                    return 0
                else
                    echo "fasterq-dump succeeded but no FASTQ files created for $srr on attempt \$attempt" >&2
                    cat error.log >&2
                    return 1
                fi
            else
                echo "fasterq-dump failed for $srr on attempt \$attempt" >&2
                cat error.log >&2
                return 1
            fi
        else
            echo "Prefetch failed for $srr on attempt \$attempt" >&2
            cat error.log >&2
            return 1
        fi
    }
    
    # Try download with retries
    success=false
    for attempt in 1 2 3; do
        if attempt_download \$attempt; then
            success=true
            break
        else
            if [ \$attempt -lt 3 ]; then
                echo "Waiting 60 seconds before retry..."
                sleep 60
            fi
        fi
    done
    
    # Handle final result
    if [ "\$success" = true ]; then
        echo "Successfully downloaded $srr"
        rm -f error.log
        # Create empty failure file to satisfy optional output
        touch failed_${srr}.txt
    else
        echo "ERROR: All download attempts failed for $srr" >&2
        echo -e "$srr\tPE\tPrefetch failed after 3 attempts" > failed_${srr}.txt
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
    errorStrategy 'retry'
    maxRetries 3
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}.fastq"), optional: true
    path "failed_${srr}.txt", optional: true
    
    script:
    """
    # Function to attempt download with prefetch + fasterq-dump
    attempt_download() {
        local attempt=\$1
        echo "Attempt \$attempt: Downloading $srr with prefetch"

        # Clean up any partial files from previous attempts
        rm -f ${srr}.fastq
        rm -rf ${srr}/
        rm -f ${srr}.sra
        
        # Step 1: Use prefetch
        echo "Step 1: Using prefetch for $srr"
        if prefetch $srr 1>/dev/null 2>error.log; then
            echo "Prefetch successful for $srr"
            
            # Step 2: Convert SRA to FASTQ using fasterq-dump
            echo "Step 2: Converting SRA to FASTQ for $srr"
            if fasterq-dump $srr --split-files -O . 1>/dev/null 2>>error.log; then
                # Check if we actually got files
                if ls ${srr}.fastq 1> /dev/null 2>&1; then
                    echo "Complete download successful for $srr on attempt \$attempt"
                    # Clean up SRA file to save space
                    rm -rf ${srr}/
                    rm -f ${srr}.sra
                    return 0
                else
                    echo "fasterq-dump succeeded but no FASTQ files created for $srr on attempt \$attempt" >&2
                    cat error.log >&2
                    return 1
                fi
            else
                echo "fasterq-dump failed for $srr on attempt \$attempt" >&2
                cat error.log >&2
                return 1
            fi
        else
            echo "Prefetch failed for $srr on attempt \$attempt" >&2
            cat error.log >&2
            return 1
        fi
    }
    
    # Try download with retries
    success=false
    for attempt in 1 2 3; do
        if attempt_download \$attempt; then
            success=true
            break
        else
            if [ \$attempt -lt 3 ]; then
                echo "Waiting 60 seconds before retry..."
                sleep 60
            fi
        fi
    done
    
    # Handle final result
    if [ "\$success" = true ]; then
        echo "Successfully downloaded $srr"
        rm -f error.log
        # Create empty failure file to satisfy optional output
        touch failed_${srr}.txt
    else
        echo "ERROR: All download attempts failed for $srr" >&2
        echo -e "$srr\tSE\tPrefetch failed after 3 attempts" > failed_${srr}.txt
        # Create dummy output files to satisfy the tuple output
        touch ${srr}.fastq
        exit 1
    fi
    """
}


// Process to collect all failure reports
process CollectFailedDownloads {
    tag "Collecting failed download reports"
    publishDir "${params.outdir}", mode: 'copy'
    errorStrategy 'ignore'

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