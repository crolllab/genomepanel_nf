process addRG {
    tag "PICARD adding ReadGroup: ${run_id} -> ${sample_name}"
    errorStrategy 'retry'
    maxRetries 6

    input:
    tuple val(run_id), val(sample_name), val(library_id), path(sorted_bam), path(sorted_bai)

    output:
    tuple val(sample_name), val(run_id), path("${run_id}_RG.bam"), emit: bam

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

    # Delete the sorted BAM and BAI files (resolve symlinks to actual files)
    bam_target="\$(readlink -f "$sorted_bam")"
    bai_target="\$(readlink -f "$sorted_bai")"
    [ -n "\$bam_target" ] && [ -f "\$bam_target" ] && rm "\$bam_target" || true
    [ -n "\$bai_target" ] && [ -f "\$bai_target" ] && rm "\$bai_target" || true
    """
}
