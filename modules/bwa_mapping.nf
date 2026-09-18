process bwaMap {
    tag "BWA-mem mapping"
    // Per-sample step: once retries run out the run is dropped (and named in
    // ignored_samples.txt) instead of aborting every other sample.
    errorStrategy { task.attempt <= 6 ? 'retry' : 'ignore' }
    maxRetries 6
        
    input:
    path reference
    file "${reference}.amb"
    file "${reference}.ann"
    file "${reference}.bwt.2bit.64"
    file "${reference}.pac"
    file "${reference}.0123"
    // consumed: the trimmed reads, deleted by the workflow once this task's
    // output is accepted (see modules/delete_intermediates.nf)
    tuple val(sample_id), path(trimmed_reads), val(consumed)
    
    output:
    tuple val(sample_id), path("${sample_id}.sam"), val(consumed), emit: sam
    
    script:
    // Build bwa-mem input dynamically
    def reads_cmd = trimmed_reads.size() == 2 ? "${trimmed_reads[0]} ${trimmed_reads[1]}" : "${trimmed_reads[0]}"
    """
    bwa-mem2 mem -t $task.cpus $reference $reads_cmd > ${sample_id}.sam
    """
}
