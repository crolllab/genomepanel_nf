process trimSequencesPE {
    maxForks = 20
    tag "FASTP PE trimming"
    errorStrategy 'ignore'
    memory '4GB'
    cpus 16
      
    input:
    tuple val(sample_id), path(reads)
  
    output:
    tuple val(sample_id), path("${sample_id}_{1,2}_trimmed.fastq.gz")

    script:
    """
    fastp -w $task.cpus -i ${reads[0]} -I ${reads[1]} -o ${sample_id}_1_trimmed.fastq.gz -O ${sample_id}_2_trimmed.fastq.gz
    """
}

process trimSequencesSE {
    maxForks = 20
    tag "FASTP SE trimming"
    errorStrategy 'ignore'
    memory '4GB'
    cpus 16

    input:
    tuple val(sample_id), path(r1)

    output:
    tuple val(sample_id), path("${sample_id}_trimmed.fastq.gz")

    script:
    """
    fastp -w $task.cpus \
        -i $r1 \
        -o ${sample_id}_trimmed.fastq.gz
    """
}