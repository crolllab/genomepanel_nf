process samtoolsSort {
    tag "Sorting BAM files for $sample_id"
    memory '16GB'
    errorStrategy 'ignore'
    cpus 1
    publishDir "${params.outdir}/bwa", mode: 'copy', pattern: "*.json"
    
    input:
    tuple val(sample_id), path(sample_sam)
    
    output:
    tuple val(sample_id), path("${sample_id}_sorted.bam"), path("${sample_id}_sorted.bam.bai"), emit: bam
    path "${sample_id}_flagstat.json", emit: report
    
    script:
    """
    samtools flagstat -O json $sample_sam > ${sample_id}_flagstat.json
    # Convert SAM to BAM, filter out low-quality alignments (MAPQ < 10)
    samtools view -Sb -q 10 $sample_sam | samtools sort --threads $task.cpus -o ${sample_id}_sorted.bam -
    samtools index ${sample_id}_sorted.bam
    """
}