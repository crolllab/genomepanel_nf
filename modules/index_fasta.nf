process fastaIndex {
    time '1d'
    tag "Reference FASTA index building"    
    cpus 1
    memory { 2.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 3
    
    beforeScript """
        mkdir -p "\$PWD/tmp"
        export TMPDIR="\$PWD/tmp"
    """
    
    input:
    path reference

    output:
    file "${reference.baseName}.fasta.fai"

    script:
    """
    samtools faidx $reference
    """
}
