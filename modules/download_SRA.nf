// Robust SRA download process that gracefully handles failures
process SRAdownloadPE {
    cpus 1
    memory '4GB'
    tag "Downloading $srr from NCBI SRA (PE)"
    errorStrategy 'ignore'  // Don't fail pipeline on download errors
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}_*.fastq"), path(".download_status"), emit: reads
    
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
    
    # Always create status file and dummy outputs for failures
    if [ \$success -eq 1 ]; then
        echo "SUCCESS" > .download_status
        echo "SUCCESS: $srr downloaded successfully"
    else
        echo "FAILED" > .download_status
        # Create empty dummy files to satisfy output requirements
        touch ${srr}_1.fastq ${srr}_2.fastq
        
        echo "WARNING: Failed to download $srr after 3 attempts - skipping"
        # Log failure details in status file
        echo "Download failed after 3 attempts" >> .download_status
        if [ -f error_3.log ]; then
            echo "---" >> .download_status
            tail -5 error_3.log >> .download_status 2>/dev/null
        fi
    fi
    
    # Always exit successfully - failures handled by status file
    exit 0
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
    tuple val(srr), path("${srr}.fastq"), path(".download_status"), emit: reads
    
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
    
    # Always create status file and dummy outputs for failures
    if [ \$success -eq 1 ]; then
        echo "SUCCESS" > .download_status
        echo "SUCCESS: $srr downloaded successfully"
    else
        echo "FAILED" > .download_status
        # Create empty dummy file to satisfy output requirements
        touch ${srr}.fastq
        
        echo "WARNING: Failed to download $srr after 3 attempts - skipping"
        # Log failure details in status file
        echo "Download failed after 3 attempts" >> .download_status
        if [ -f error_3.log ]; then
            echo "---" >> .download_status
            tail -5 error_3.log >> .download_status 2>/dev/null
        fi
    fi
    
    # Always exit successfully - failures handled by status file
    exit 0
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
    path "NCBI_download_summary.tsv"
    
    script:
    """
    echo -e "SRR_ID\tType\tStatus\tError_Details" > NCBI_download_summary.tsv
    
    failed_count=0
    success_count=0
    
    # Process all status files
    for status_file in .download_status*; do
        if [ -f "\$status_file" ]; then
            first_line=\$(head -n1 "\$status_file")
            
            # Extract type from filename pattern if available
            type="Unknown"
            
            if echo "\$first_line" | grep -q "SUCCESS"; then
                ((success_count++))
            elif echo "\$first_line" | grep -q "FAILED"; then
                ((failed_count++))
                # Extract error details (everything after first line)
                error_details=\$(tail -n +2 "\$status_file" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')
                # Try to extract SRR from filename or use placeholder
                srr_id=\$(echo "\$status_file" | grep -oP 'SRR[0-9]+' || echo "Unknown")
                echo -e "\$srr_id\t\$type\tFailed\t\$error_details" >> NCBI_download_summary.tsv
            fi
        fi
    done
    
    echo "" >> NCBI_download_summary.tsv
    echo "====================================" >> NCBI_download_summary.tsv
    echo "Summary:" >> NCBI_download_summary.tsv
    echo "  Successful downloads: \$success_count" >> NCBI_download_summary.tsv
    echo "  Failed downloads: \$failed_count" >> NCBI_download_summary.tsv
    echo "  Total attempted: \$((success_count + failed_count))" >> NCBI_download_summary.tsv
    
    if [ \$failed_count -gt 0 ]; then
        echo "" >> NCBI_download_summary.tsv
        echo "WARNING: \$failed_count samples were excluded from downstream analysis" >> NCBI_download_summary.tsv
        echo "Check error details above for troubleshooting" >> NCBI_download_summary.tsv
    fi
    """
}