process samtoolsSort {
    tag "Sorting BAM files"
    memory '16GB'
    errorStrategy 'ignore'
    cpus 1
    publishDir "${params.outdir}/bwa", mode: 'copy', pattern: "*.json"

    input:
    path sample_sam

    output:
    tuple val("${sample_sam.baseName}"), path("${sample_sam.baseName}{_sorted.bam,_sorted.bam.bai}")
    path "${sample_sam.baseName}_flagstat.json", emit: report


    script:
    """
    samtools flagstat -O json $sample_sam > ${sample_sam.baseName}_flagstat.json
    # Convert SAM to BAM, filter out low-quality alignments (MAPQ < 10
    samtools view -Sb -q 10 $sample_sam | samtools sort --threads $task.cpus -o ${sample_sam.baseName}_sorted.bam -
    #rm "\$(readlink -f "${sample_sam}")"
    samtools index ${sample_sam.baseName}_sorted.bam
    """
}
