process fastaIndex {
    tag "Reference FASTA index building"    
    errorStrategy 'retry'
    maxRetries 3
    
    beforeScript """
        mkdir -p "\$PWD/tmp"
        export TMPDIR="\$PWD/tmp"
    """
    
    input:
    path reference

    output:
    file "${reference}.fai"

    script:
    """
    samtools faidx $reference
    """
}
