// Robust SRA download process that gracefully handles failures
process SRAdownloadPE {
    cpus 1
    memory '4GB'
    tag "Downloading $srr from NCBI SRA (PE)"
    errorStrategy 'ignore'  // Don't fail pipeline on download errors
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}_*.fastq"), optional: true, emit: reads
    path "failed_${srr}.txt", optional: true, emit: failures
    
    script:
    """
    set +e  # Don't exit on command failures
    
    # Function to attempt download
    attempt_download() {
        local attempt=\$1
        echo "[Attempt \$attempt/3] Downloading $srr (PE)"
        
        # Clean up any partial files
        rm -rf ${srr}/ ${srr}.sra ${srr}_*.fastq 2>/dev/null
        
        # Try prefetch (with timeout)
        if timeout 300 prefetch $srr 2>error_\${attempt}.log; then
            # Try fasterq-dump (with timeout)
            if timeout 600 fasterq-dump $srr --split-files -O . 2>>error_\${attempt}.log; then
                # Verify files exist and are not empty
                if compgen -G "${srr}_*.fastq" > /dev/null; then
                    local file_count=\$(ls ${srr}_*.fastq 2>/dev/null | wc -l)
                    if [ "\$file_count" -ge 2 ]; then
                        echo "✓ Successfully downloaded $srr (PE) on attempt \$attempt"
                        rm -rf ${srr}/ ${srr}.sra error_*.log 2>/dev/null
                        return 0
                    fi
                fi
            fi
        fi
        
        echo "✗ Attempt \$attempt failed for $srr"
        return 1
    }
    
    # Try download up to 3 times
    success=0
    for attempt in 1 2 3; do
        if attempt_download \$attempt; then
            success=1
            break
        fi
        [ \$attempt -lt 3 ] && sleep 30  # Brief pause between attempts
    done
    
    # Handle result
    if [ \$success -eq 1 ]; then
        echo "SUCCESS: $srr downloaded successfully"
        exit 0
    else
        echo "WARNING: Failed to download $srr after 3 attempts - skipping"
        # Log failure details
        echo -e "$srr\tPE\tDownload failed after 3 attempts" > failed_${srr}.txt
        if [ -f error_3.log ]; then
            echo "Last error:" >> failed_${srr}.txt
            tail -5 error_3.log >> failed_${srr}.txt 2>/dev/null
        fi
        # Exit successfully so pipeline continues
        exit 0
    fi
    """
}

process SRAdownloadSE {
    cpus 1
    memory '4GB'
    tag "Downloading $srr from NCBI SRA (SE)"
    errorStrategy 'ignore'  // Don't fail pipeline on download errors
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}.fastq"), optional: true, emit: reads
    path "failed_${srr}.txt", optional: true, emit: failures
    
    script:
    """
    set +e  # Don't exit on command failures
    
    # Function to attempt download
    attempt_download() {
        local attempt=\$1
        echo "[Attempt \$attempt/3] Downloading $srr (SE)"
        
        # Clean up any partial files
        rm -rf ${srr}/ ${srr}.sra ${srr}.fastq ${srr}_*.fastq 2>/dev/null
        
        # Try prefetch (with timeout)
        if timeout 300 prefetch $srr 2>error_\${attempt}.log; then
            # Try fasterq-dump (with timeout)
            if timeout 600 fasterq-dump $srr --split-files -O . 2>>error_\${attempt}.log; then
                # For SE, the file might be named ${srr}.fastq or ${srr}_1.fastq
                if [ -f "${srr}.fastq" ] && [ -s "${srr}.fastq" ]; then
                    echo "✓ Successfully downloaded $srr (SE) on attempt \$attempt"
                    rm -rf ${srr}/ ${srr}.sra error_*.log 2>/dev/null
                    return 0
                elif [ -f "${srr}_1.fastq" ] && [ -s "${srr}_1.fastq" ]; then
                    # Rename to standard SE format
                    mv ${srr}_1.fastq ${srr}.fastq
                    rm -f ${srr}_2.fastq 2>/dev/null  # Remove unexpected second file
                    echo "✓ Successfully downloaded $srr (SE) on attempt \$attempt"
                    rm -rf ${srr}/ ${srr}.sra error_*.log 2>/dev/null
                    return 0
                fi
            fi
        fi
        
        echo "✗ Attempt \$attempt failed for $srr"
        return 1
    }
    
    # Try download up to 3 times
    success=0
    for attempt in 1 2 3; do
        if attempt_download \$attempt; then
            success=1
            break
        fi
        [ \$attempt -lt 3 ] && sleep 30  # Brief pause between attempts
    done
    
    # Handle result
    if [ \$success -eq 1 ]; then
        echo "SUCCESS: $srr downloaded successfully"
        exit 0
    else
        echo "WARNING: Failed to download $srr after 3 attempts - skipping"
        # Log failure details
        echo -e "$srr\tSE\tDownload failed after 3 attempts" > failed_${srr}.txt
        if [ -f error_3.log ]; then
            echo "Last error:" >> failed_${srr}.txt
            tail -5 error_3.log >> failed_${srr}.txt 2>/dev/null
        fi
        # Exit successfully so pipeline continues
        exit 0
    fi
    """
}


// Process to collect and summarize all failure reports
process CollectFailedDownloads {
    tag "Summarizing download results"
    publishDir "${params.outdir}", mode: 'copy'
    errorStrategy 'ignore'

    input:
    path failed_files
    
    output:
    path "NCBI_download_summary.tsv", optional: true
    
    script:
    """
    # Count failures
    failure_count=0
    if compgen -G "failed_*.txt" > /dev/null; then
        failure_count=\$(ls failed_*.txt 2>/dev/null | wc -l)
    fi
    
    if [ \$failure_count -gt 0 ]; then
        echo "Found \$failure_count failed downloads"
        echo -e "SRR_ID\tType\tError_Details" > NCBI_download_summary.tsv
        
        # Combine all failure files
        for file in failed_*.txt; do
            if [ -f "\$file" ] && [ -s "\$file" ]; then
                cat "\$file" >> NCBI_download_summary.tsv
            fi
        done
        
        echo "====================================" >> NCBI_download_summary.tsv
        echo "Total failed downloads: \$failure_count" >> NCBI_download_summary.tsv
        echo "Pipeline continued with successfully downloaded samples" >> NCBI_download_summary.tsv
    else
        echo "All SRA downloads completed successfully"
        # Don't create output file if all succeeded
    fi
    """
}