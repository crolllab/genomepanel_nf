process trimSequencesPE {
    tag "FASTP PE trimming"
    errorStrategy 'ignore'
    memory '4GB'
    publishDir "${params.outdir}/fastp_stats", mode: 'copy', pattern: "*.json"
        
    input:
    tuple val(sample_id), path(read1), path(read2)
    
    output:
    tuple val(sample_id), path("${sample_id}_*_trimmed.fastq.gz"), emit: reads
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
    
    # Safely delete the original input files after trimming
    # Uses safe deletion pattern to prevent race conditions
    for file in "$read1" "$read2"; do
        if [ -L "\$file" ]; then
            # Resolve symlink to actual file
            target=\$(readlink -f "\$file" 2>/dev/null)
            [ -n "\$target" ] && [ -f "\$target" ] && rm "\$target" || true
        elif [ -f "\$file" ]; then
            # Direct file deletion
            rm "\$file" || true
        fi
    done
    """
}

process trimSequencesSE {
    tag "FASTP SE trimming"
    errorStrategy 'ignore'
    memory '4GB'
    cpus 4
    publishDir "${params.outdir}/fastp_stats", mode: 'copy', pattern: "*.json"

    beforeScript """
        mkdir -p "\$PWD/tmp"
        export TMPDIR="\$PWD/tmp"
    """

    input:
    tuple val(sample_id), path(r1)
    
    output:
    tuple val(sample_id), path("${sample_id}_trimmed.fastq.gz"), emit: reads
    path "${sample_id}_SE_fastp.json", emit: report
    
    script:
    """
    fastp \
        -w $task.cpus \
        -i $r1 \
        -o ${sample_id}_trimmed.fastq.gz \
        --json ${sample_id}_SE_fastp.json
    
    # Safely delete the original input file after trimming
    # Uses safe deletion pattern to prevent race conditions
    if [ -L "$r1" ]; then
        # Resolve symlink to actual file
        target=\$(readlink -f "$r1" 2>/dev/null)
        [ -n "\$target" ] && [ -f "\$target" ] && rm "\$target" || true
    elif [ -f "$r1" ]; then
        # Direct file deletion
        rm "$r1" || true
    fi
    """
}