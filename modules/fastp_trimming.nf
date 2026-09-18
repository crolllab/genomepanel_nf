process trimSequencesPE {
    tag "FASTP PE trimming"
    errorStrategy { task.attempt <= 3 ? 'retry' : 'ignore' }
    maxRetries 6
    publishDir "${params.outdir}/3_fastq_stats", mode: 'copy', pattern: "*.json"
        
    input:
    // consumed: the upstream files this task reads, deleted by the workflow
    // once the output is accepted (see modules/delete_intermediates.nf).
    // Empty for user-provided reads, which are never deleted.
    tuple val(sample_id), path(read1), path(read2), val(consumed)
    
    output:
    tuple val(sample_id), path("${sample_id}_*_trimmed.fastq.gz"), val(consumed), emit: reads
    path "${sample_id}_PE_fastp.json", emit: report
    
    script:
    """
    fastp \
        -w $task.cpus \
        -i $read1 \
        -I $read2 \
        -o ${sample_id}_1_trimmed.fastq.gz \
        -O ${sample_id}_2_trimmed.fastq.gz \
        --json ${sample_id}_PE_fastp.json
    """
}

process trimSequencesSE {
    tag "FASTP SE trimming"
    errorStrategy { task.attempt <= 3 ? 'retry' : 'ignore' }
    maxRetries 6
    publishDir "${params.outdir}/3_fastq_stats", mode: 'copy', pattern: "*.json"

    beforeScript """
        mkdir -p "\$PWD/tmp"
        export TMPDIR="\$PWD/tmp"
    """

    input:
    tuple val(sample_id), path(r1), val(consumed)
    
    output:
    tuple val(sample_id), path("${sample_id}_trimmed.fastq.gz"), val(consumed), emit: reads
    path "${sample_id}_SE_fastp.json", emit: report
    
    script:
    """
    fastp \
        -w $task.cpus \
        -i $r1 \
        -o ${sample_id}_trimmed.fastq.gz \
        --json ${sample_id}_SE_fastp.json
    """
}
