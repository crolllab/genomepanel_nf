// =============================================================================
//  PacBio HiFi read mapping with pbmm2 (EXPERIMENTAL)
// =============================================================================
//  HiFi runs (--hifi_reads, --hifi_SRA_index) take their own path from reads to
//  a read-grouped BAM, then join the Illumina runs at the per-sample merge in
//  gp_wf.nf:
//
//    pbmm2Index (once)  ->  pbmm2Map (per run)  ->  hifiFlagstat  ->  rg_bams
//
//  No trimming: HiFi reads are already consensus-called and adapter-free, and
//  fastp is a short-read tool. No addRG either: pbmm2 writes the read group
//  itself (PL:PACBIO), whereas addRG would stamp PL:ILLUMINA over it.
//
//  The read group carries the same SM as any Illumina run of the sample, so
//  mergeRunBAMs puts both in one BAM and GATK calls them as one sample. Its ID
//  and LB are the HiFi run's own: MarkDuplicates scopes to the library, and
//  never comparing a HiFi read with an Illumina read is what keeps a 15 kb
//  molecule from being marked as a duplicate of a 150 bp one.
// =============================================================================

// minimap2 index of the reference, built once and shared by every HiFi run.
// The index is preset-specific (k-mer size, window, homopolymer compression),
// so it must be built with the same --preset as pbmm2Map aligns with.
process pbmm2Index {
    tag "Reference pbmm2 index building"
    errorStrategy 'retry'
    maxRetries 6

    input:
    path reference

    output:
    path "${reference.baseName}.mmi"

    script:
    """
    pbmm2 index -j ${task.cpus} --preset CCS ${reference} ${reference.baseName}.mmi
    """
}

process pbmm2Map {
    tag "pbmm2 HiFi mapping: ${run_id} -> ${sample_name}"
    // Per-run step: once retries run out the run is dropped (and named in
    // ignored_samples.txt) instead of aborting every other sample.
    errorStrategy { task.attempt <= 6 ? 'retry' : 'ignore' }
    maxRetries 6

    input:
    path reference_mmi
    // consumed: downloaded HiFi reads, deleted by the workflow once this run's
    // BAM is accepted (see modules/delete_intermediates.nf). Empty for
    // --hifi_reads, which belong to the user.
    tuple val(run_id), val(sample_name), val(library_id), path(reads), val(consumed)

    output:
    tuple val(run_id), val(sample_name), path("${run_id}_pbmm2.bam"), val(consumed), emit: bam

    script:
    // pbmm2 runs -j alignment threads plus -J sort threads, so split the
    // task's CPUs between them rather than oversubscribing the allocation.
    def sort_threads  = Math.max(1, task.cpus.intdiv(4))
    def align_threads = Math.max(1, task.cpus - sort_threads)
    // --bam-index NONE: nothing reads this BAM by region -- hifiFlagstat,
    // mergeRunBAMs and dupRemoval all stream it, and dupRemoval indexes its
    // own output.
    // --unmapped: pbmm2 otherwise leaves unmapped reads out altogether, so
    // every HiFi run would report a 100% mapping rate. HaplotypeCaller skips
    // them, as it does bwa-mem2's unmapped reads.
    """
    mkdir -p tmp
    export TMPDIR="\$PWD/tmp"

    pbmm2 align ${reference_mmi} ${reads} ${run_id}_pbmm2.bam \\
        --preset CCS \\
        --rg '@RG\\tID:${run_id}\\tSM:${sample_name}\\tLB:${library_id}\\tPL:PACBIO' \\
        --sort \\
        --bam-index NONE \\
        --unmapped \\
        -j ${align_threads} \\
        -J ${sort_threads} \\
        --log-level INFO
    """
}

// Mapping statistics for the HiFi runs, in the same flagstat JSON form that
// samtoolsSort writes for Illumina runs, so both end up in bwa_summary.tsv
// and the report. A separate process only because the pbmm2 container has no
// samtools. gp_wf.nf holds each HiFi BAM back until this has finished with
// it, so the BAM cannot be merged -- and deleted -- while it is being read.
process hifiFlagstat {
    tag "HiFi mapping stats: ${run_id}"
    errorStrategy { task.attempt <= 6 ? 'retry' : 'ignore' }
    maxRetries 6
    publishDir "${params.outdir}/4_bwa_mapping", mode: 'copy', pattern: "*.json"

    input:
    tuple val(run_id), path(bam)

    output:
    tuple val(run_id), path("${run_id}_HiFi_flagstat.json"), emit: report

    script:
    """
    samtools flagstat -@ ${task.cpus} -O json ${bam} > ${run_id}_HiFi_flagstat.json
    """
}
