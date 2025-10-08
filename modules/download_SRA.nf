// Hybrid download for paired-end reads: tries ENA URL first, falls back to NCBI
process SRAdownloadPE {
    cpus 1
    memory '4GB'
    tag "Downloading PE: $srr"
    errorStrategy 'ignore'
    
    input:
    tuple val(srr), val(url1), val(url2), val(source)
    
    output:
    tuple val(srr), path("${srr}_1.fastq*"), path("${srr}_2.fastq*")
    
    script:
    """
    #!/bin/bash
    set -e
    
    # Configure SRA-tools to use current directory for temp files
    export NCBI_SETTINGS="\$PWD/.ncbi"
    mkdir -p "\$NCBI_SETTINGS"
    
    # Create config to use current directory for cache and temp
    cat > "\$NCBI_SETTINGS/user-settings.mkfg" << EOF
/repository/user/main/public/root = "\$PWD"
/repository/user/main/public/cache-enabled = "false"
EOF
    
    echo "Downloading $srr from $source"
    
    # Try ENA direct download if URLs are available
    if [[ -n "$url1" && -n "$url2" && "$source" == "ENA" ]]; then
        echo "Attempting ENA direct download..."
        
        if wget -q -O ${srr}_1.fastq.gz "$url1" && wget -q -O ${srr}_2.fastq.gz "$url2"; then
            # Verify files are not empty
            if [ -s "${srr}_1.fastq.gz" ] && [ -s "${srr}_2.fastq.gz" ]; then
                echo "✓ Successfully downloaded from ENA"
                exit 0
            else
                echo "⚠ ENA files empty, falling back to NCBI"
                rm -f ${srr}_*.fastq.gz
            fi
        else
            echo "⚠ ENA download failed, falling back to NCBI"
            rm -f ${srr}_*.fastq.gz
        fi
    fi
    
    # Fallback to NCBI prefetch/fasterq-dump
    echo "Downloading from NCBI..."
    
    # Create explicit download directory to avoid /tmp/ quota issues
    # prefetch creates subdirectory, so we control the parent location
    mkdir -p ncbi_download
    
    # Use explicit output file path (not --output-directory which creates subdirs)
    # This ensures download happens in work directory, not /tmp/
    prefetch $srr --output-file ncbi_download/${srr}.sra
    
    # Decompress with explicit temp directory in work location
    fasterq-dump ncbi_download/${srr}.sra --split-files -O . --temp .
    
    # Clean up SRA file immediately to save space
    rm -rf ncbi_download
    
    # Verify we got paired-end files
    if [ ! -f "${srr}_1.fastq" ] || [ ! -f "${srr}_2.fastq" ]; then
        echo "ERROR: Expected PE files not found for $srr"
        exit 1
    fi
    
    # Check files are not empty
    if [ ! -s "${srr}_1.fastq" ] || [ ! -s "${srr}_2.fastq" ]; then
        echo "ERROR: Empty fastq files for $srr"
        exit 1
    fi
    
    echo "✓ Successfully downloaded from NCBI"
    """
}

// Hybrid download for single-end reads: tries ENA URL first, falls back to NCBI
process SRAdownloadSE {
    cpus 1
    memory '4GB'
    tag "Downloading SE: $srr"
    errorStrategy 'ignore'
    
    input:
    tuple val(srr), val(url1), val(source)
    
    output:
    tuple val(srr), path("${srr}.fastq*")
    
    script:
    """
    #!/bin/bash
    set -e
    
    # Configure SRA-tools to use current directory for temp files
    export NCBI_SETTINGS="\$PWD/.ncbi"
    mkdir -p "\$NCBI_SETTINGS"
    
    # Create config to use current directory for cache and temp
    cat > "\$NCBI_SETTINGS/user-settings.mkfg" << EOF
/repository/user/main/public/root = "\$PWD"
/repository/user/main/public/cache-enabled = "false"
EOF
    
    echo "Downloading $srr from $source"
    
    # Try ENA direct download if URL is available
    if [[ -n "$url1" && "$source" == "ENA" ]]; then
        echo "Attempting ENA direct download..."
        
        if wget -q -O ${srr}.fastq.gz "$url1"; then
            # Verify file is not empty
            if [ -s "${srr}.fastq.gz" ]; then
                echo "✓ Successfully downloaded from ENA"
                exit 0
            else
                echo "⚠ ENA file empty, falling back to NCBI"
                rm -f ${srr}.fastq.gz
            fi
        else
            echo "⚠ ENA download failed, falling back to NCBI"
            rm -f ${srr}.fastq.gz
        fi
    fi
    
    # Fallback to NCBI prefetch/fasterq-dump
    echo "Downloading from NCBI..."
    
    # Create explicit download directory to avoid /tmp/ quota issues
    mkdir -p ncbi_download
    
    # Use explicit output file path to ensure download in work directory
    prefetch $srr --output-file ncbi_download/${srr}.sra
    
    # Decompress with explicit temp directory in work location
    fasterq-dump ncbi_download/${srr}.sra --split-files -O . --temp .
    
    # Clean up SRA file immediately
    rm -rf ncbi_download
    
    # Handle SE naming variations (might be .fastq or _1.fastq)
    if [ -f "${srr}.fastq" ]; then
        echo "Found ${srr}.fastq"
    elif [ -f "${srr}_1.fastq" ]; then
        echo "Found ${srr}_1.fastq, renaming to ${srr}.fastq"
        mv ${srr}_1.fastq ${srr}.fastq
        rm -f ${srr}_2.fastq 2>/dev/null || true
    else
        echo "ERROR: No fastq file found for $srr"
        exit 1
    fi
    
    # Check file is not empty
    if [ ! -s "${srr}.fastq" ]; then
        echo "ERROR: Empty fastq file for $srr"
        exit 1
    fi
    
    echo "✓ Successfully downloaded from NCBI"
    """
}
