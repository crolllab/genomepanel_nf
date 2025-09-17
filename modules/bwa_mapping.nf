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
    tuple val(sample_id), path("${sample_id}.sam"), emit: sam

    script:
    // Build bwa-mem input dynamically
    def reads_cmd = trimmed_reads.size() == 2 ? "${trimmed_reads[0]} ${trimmed_reads[1]}" : "${trimmed_reads[0]}"
    """
    bwa-mem2 mem -t $task.cpus $reference $reads_cmd > ${sample_id}.sam
    """
}
