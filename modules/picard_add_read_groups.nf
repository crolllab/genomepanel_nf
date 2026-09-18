process addRG {
    tag "PICARD adding ReadGroup: ${run_id} -> ${sample_name}"
    errorStrategy { task.attempt <= 6 ? 'retry' : 'ignore' }
    maxRetries 6

    input:
    // consumed: the sorted BAM and index, deleted by the workflow once this
    // task's output is accepted (see modules/delete_intermediates.nf)
    tuple val(run_id), val(sample_name), val(library_id), path(sorted_bam), path(sorted_bai), val(consumed)

    output:
    tuple val(sample_name), val(run_id), path("${run_id}_RG.bam"), val(consumed), emit: bam

    script:
    // sample_name and library_id are resolved once, in Groovy, by gp_wf.nf
    // (see the sample_of/library_of maps built from --SRR_sample_map). That is
    // what lets Nextflow group runs by their RESOLVED sample name afterwards,
    // to merge every run of one sample before duplicate marking -- a shell-side
    // lookup here (the previous design) makes the resolved name invisible to
    // Nextflow, so two runs of the same sample stay two separate BAMs, two
    // separate gVCFs, and a GenomicsDBImport rejection later on ("duplicate
    // sample" — the 2026-09-04 lepus incident).
    //
    // RGLB defaults to a per-run library id (sample_name + run_id) rather than
    // a single library shared by every run of a sample: with no other evidence,
    // assuming every run is the same library is not safe (duplicate marking
    // scopes to the library), and MarkDuplicates degrades gracefully if runs
    // really do share a library. Give the map file a third column
    // (Run_ID,Sample_Name,Library_ID) to state the true library instead.
    """
    picard -Xmx${task.memory.toGiga()-2}g AddOrReplaceReadGroups \
        -INPUT $sorted_bam \
        -OUTPUT ${run_id}_RG.bam \
        -RGID ${run_id} \
        -RGLB ${library_id} \
        -RGPL ILLUMINA \
        -RGPU unit1 \
        -RGSM ${sample_name} \
        --VALIDATION_STRINGENCY SILENT
    """
}
