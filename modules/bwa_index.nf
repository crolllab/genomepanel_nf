process bwaIndex {
    tag "Reference BWA index building"    
    errorStrategy 'retry'
    maxRetries 3

    input:
    path reference
    
    output:
    file "${reference.baseName}.fasta.amb"
    file "${reference.baseName}.fasta.ann"
    file "${reference.baseName}.fasta.bwt.2bit.64"
    file "${reference.baseName}.fasta.pac"
    file "${reference.baseName}.fasta.0123"    

    script:
    """
    bwa-mem2 index $reference 
    """
}
