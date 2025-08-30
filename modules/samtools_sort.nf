process samtoolsSort {
    tag "Sorting BAM files"
    memory '16GB'
    errorStrategy 'ignore'
    cpus 1

    input:
    path sample_sam

    output:
    tuple val("${sample_sam.baseName}"), path("${sample_sam.baseName}{_sorted.bam,_sorted.bam.bai}")
    
    script:
    """
    samtools view -Sb -q 10 $sample_sam | samtools sort --threads $task.cpus -o ${sample_sam.baseName}_sorted.bam -
    #rm "\$(readlink -f "${sample_sam}")"
    samtools index ${sample_sam.baseName}_sorted.bam
    """
}
