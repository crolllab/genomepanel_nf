process trimSequencesPE {
    tag "FASTP PE trimming"
    errorStrategy 'ignore'
    memory '4GB'
    cpus 4
    publishDir "${params.outdir}/fastp_stats", mode: 'copy', pattern: "*.json"
    
    input:
    tuple val(sample_id), path(read1), path(read2)
    
    output:
    tuple val(sample_id), path("${sample_id}_{1,2}_trimmed.fastq.gz"), emit: reads
    path "${sample_id}_fastp.json", emit: report
    
    script:
    """
    fastp \
        -w $task.cpus \
        -i $read1 \
        -I $read2 \
        -o ${sample_id}_1_trimmed.fastq.gz \
        -O ${sample_id}_2_trimmed.fastq.gz \
        --json ${sample_id}_fastp.json
    
    # Safely delete the original input files, ignoring write-protection errors
    for file in "$read1" "$read2"; do
        if [ -L "\$file" ]; then
            # It's a symlink - try to delete the target
            target=\$(readlink -f "\$file" 2>/dev/null)
            if [ -n "\$target" ] && [ -f "\$target" ]; then
                rm "\$target" 2>/dev/null || echo "Warning: Could not delete \$target (write-protected or permission denied)"
            fi
        elif [ -f "\$file" ]; then
            # It's a regular file - try to delete it directly
            rm "\$file" 2>/dev/null || echo "Warning: Could not delete \$file (write-protected or permission denied)"
        fi
    done
    """
}

process trimSequencesSE {
    tag "FASTP SE trimming"
    errorStrategy 'ignore'
    memory '4GB'
    cpus 4
    publishDir "${params.outdir}/fastp", mode: 'copy', pattern: "*.json"
    
    input:
    tuple val(sample_id), path(r1)
    
    output:
    tuple val(sample_id), path("${sample_id}_trimmed.fastq.gz"), emit: reads
    path "${sample_id}_fastp.json", emit: report
    
    script:
    """
    fastp \
        -w $task.cpus \
        -i $r1 \
        -o ${sample_id}_trimmed.fastq.gz \
        --json ${sample_id}_fastp.json
    
    # Safely delete the original input file, ignoring write-protection errors
    if [ -L "$r1" ]; then
        # It's a symlink - try to delete the target
        target=\$(readlink -f "$r1" 2>/dev/null)
        if [ -n "\$target" ] && [ -f "\$target" ]; then
            rm "\$target" 2>/dev/null || echo "Warning: Could not delete \$target (write-protected or permission denied)"
        fi
    elif [ -f "$r1" ]; then
        # It's a regular file - try to delete it directly
        rm "$r1" 2>/dev/null || echo "Warning: Could not delete $r1 (write-protected or permission denied)"
    fi
    """
}