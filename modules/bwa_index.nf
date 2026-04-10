process bwaIndex {
    tag "Reference BWA index building"    
    errorStrategy 'retry'
    maxRetries 3

    input:
    path reference
    
    output:
    file "${reference}.amb"
    file "${reference}.ann"
    file "${reference}.bwt.2bit.64"
    file "${reference}.pac"
    file "${reference}.0123"    

    script:
    """
    bwa-mem2 index $reference 
    """
}
