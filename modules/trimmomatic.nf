process trimSequences {
    maxForks = 20
    tag "Trimmomatic fastq files trimming"
    memory '4GB'
    cpus 16
      
    input:
    tuple val(sample_id), path(reads)
  
    output:
    tuple val(sample_id), path("${sample_id}_{1,2}_trimmed.fastq.gz")

    script:
    """
    trimmomatic PE -threads $task.cpus ${reads[0]} ${reads[1]} ${sample_id}_1_trimmed.fastq.gz ${sample_id}_2_trimmed.fastq.gz ILLUMINACLIP:TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
    """
}
