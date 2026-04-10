process bwaMap {
    tag "BWA-mem mapping"
    errorStrategy 'retry'
    maxRetries 3
        
    input:
    path reference
    file "${reference}.amb"
    file "${reference}.ann"
    file "${reference}.bwt.2bit.64"
    file "${reference}.pac"
    file "${reference}.0123"
    tuple val(sample_id), path(trimmed_reads)
    
    output:
    tuple val(sample_id), path("${sample_id}.sam"), emit: sam
    
    script:
    // Build bwa-mem input dynamically
    def reads_cmd = trimmed_reads.size() == 2 ? "${trimmed_reads[0]} ${trimmed_reads[1]}" : "${trimmed_reads[0]}"
    """
    set -e  # Exit immediately on error - prevents cleanup if command fails
    
    bwa-mem2 mem -t $task.cpus $reference $reads_cmd > ${sample_id}.sam
    
    # Only reached if bwa-mem2 succeeded - cleanup input files
    # Delete the trimmed reads files (resolve symlinks to actual files)
    for read_file in ${trimmed_reads.join(' ')}; do
        target="\$(readlink -f "\$read_file")"
        if [ -n "\$target" ] && [ -f "\$target" ]; then
            rm "\$target" || true
        fi
    done
    """
}
