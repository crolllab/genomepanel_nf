process samtoolsSort {
    tag "Sorting BAM files"
    errorStrategy { task.attempt <= 6 ? 'retry' : 'ignore' }
    maxRetries 6
    publishDir "${params.outdir}/4_bwa_mapping", mode: 'copy', pattern: "*.json"
       
    input:
    // consumed: the SAM, deleted by the workflow once this task's output is
    // accepted (see modules/delete_intermediates.nf)
    tuple val(sample_id), path(sample_sam), val(consumed)
    
    output:
    tuple val(sample_id), path("${sample_id}_sorted.bam"), path("${sample_id}_sorted.bam.bai"), val(consumed), emit: bam
    path "${sample_id}_flagstat.json", emit: report
    
    script:
    """
    samtools flagstat -O json $sample_sam > ${sample_id}_flagstat.json
    # Convert SAM to BAM (no MAPQ filtering; all reads retained). pipefail:
    # without it a failing `samtools view` still lets `sort` write a truncated
    # BAM and the task succeed -- and the SAM it read is then deleted.
    set -o pipefail
    samtools view -Sb $sample_sam | samtools sort --threads $task.cpus -o ${sample_id}_sorted.bam -
    samtools index ${sample_id}_sorted.bam
    """
}
