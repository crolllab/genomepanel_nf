// Download SRA reads directly from ENA using HTTP (faster than prefetch+fasterq-dump)
process DownloadFromURL_PE {
    cpus 1
    memory '4GB'
    tag "Downloading PE via HTTP: $srr"
    errorStrategy 'ignore'
    
    input:
    tuple val(srr), val(url1), val(url2)
    
    output:
    tuple val(srr), path("${srr}_1.fastq.gz"), path("${srr}_2.fastq.gz")
    
    script:
    """
    #!/bin/bash
    set -e
    
    echo "Downloading $srr from ENA"
    echo "URL1: $url1"
    echo "URL2: $url2"
    
    # Download R1
    wget -O ${srr}_1.fastq.gz "$url1"
    
    # Download R2
    wget -O ${srr}_2.fastq.gz "$url2"
    
    # Verify files are not empty
    if [ ! -s "${srr}_1.fastq.gz" ] || [ ! -s "${srr}_2.fastq.gz" ]; then
        echo "ERROR: Downloaded files are empty for $srr"
        exit 1
    fi
    
    echo "Successfully downloaded $srr"
    """
}

process DownloadFromURL_SE {
    cpus 1
    memory '4GB'
    tag "Downloading SE via HTTP: $srr"
    errorStrategy 'ignore'
    
    input:
    tuple val(srr), val(url1)
    
    output:
    tuple val(srr), path("${srr}.fastq.gz")
    
    script:
    """
    #!/bin/bash
    set -e
    
    echo "Downloading $srr from ENA"
    echo "URL: $url1"
    
    # Download
    wget -O ${srr}.fastq.gz "$url1"
    
    # Verify file is not empty
    if [ ! -s "${srr}.fastq.gz" ]; then
        echo "ERROR: Downloaded file is empty for $srr"
        exit 1
    fi
    
    echo "Successfully downloaded $srr"
    """
}
