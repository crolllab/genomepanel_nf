process samtoolsSort {
    time '1d'
    tag "Sorting BAM files"
    cpus 1
    memory { 2.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 3
    publishDir "${params.outdir}/bwa_stats", mode: 'copy', pattern: "*.json"
       
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
    
    # Delete the SAM file (resolve symlink to actual file)
    sam_target="\$(readlink -f "$sample_sam")"
    [ -n "\$sam_target" ] && [ -f "\$sam_target" ] && rm "\$sam_target" || true
    """
}
