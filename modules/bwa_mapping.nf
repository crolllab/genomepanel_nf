process bwaMap {
    tag "BWA-mem mapping"
    memory '4GB'
    errorStrategy 'ignore'
   
    input:
    path reference
    file "${reference.baseName}.fasta.amb"
    file "${reference.baseName}.fasta.ann"
    file "${reference.baseName}.fasta.bwt.2bit.64"
    file "${reference.baseName}.fasta.pac"
    file "${reference.baseName}.fasta.0123"    
    tuple val(sample_id), path(trimmed_reads)

    output:
    path "${sample_id}.sam"

    script:
    """
    bwa-mem2 mem -t $task.cpus $reference ${trimmed_reads[0]} ${trimmed_reads[1]} > ${sample_id}.sam
    """
}
