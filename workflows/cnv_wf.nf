nextflow.enable.dsl=2

include { CNVPreprocessIntervals } from '../modules/gatk_cnv'
include { CNVAnnotateIntervals } from '../modules/gatk_cnv'
include { CNVCollectReadCounts } from '../modules/gatk_cnv'
include { CNVFilterIntervals } from '../modules/gatk_cnv'
include { CNVContigPloidy } from '../modules/gatk_cnv'
include { CNVGermlineCaller } from '../modules/gatk_cnv'
include { CNVPostprocess } from '../modules/gatk_cnv'
include { CNVSummary } from '../modules/r_cnv_summary'

// ---------------------
// Copy-number variant calling (--cnv), GATK gCNV in cohort mode
// ---------------------
// See modules/gatk_cnv.nf for the steps. Called from gp_wf with the
// duplicate-marked BAMs of every short-read sample.
workflow cnv_wf {

    take:
    reference
    fai_index
    gatk_index
    bams          // [sample_id, bam, bai]

    main:

    exclude_ch = params.cnv_exclude_intervals
        ? channel.fromPath(params.cnv_exclude_intervals, checkIfExists: true).collect()
        : channel.value([])
    priors_ch = params.cnv_contig_ploidy_priors
        ? channel.fromPath(params.cnv_contig_ploidy_priors, checkIfExists: true).collect()
        : channel.value([])
    annotation_ch = params.cnv_gene_annotation
        ? channel.fromPath(params.cnv_gene_annotation, checkIfExists: true).collect()
        : channel.value([])

    bins      = CNVPreprocessIntervals(reference, fai_index, gatk_index, exclude_ch)
    annotated = CNVAnnotateIntervals(reference, fai_index, gatk_index, bins)

    CNVCollectReadCounts(reference, fai_index, gatk_index, bins, bams)

    // The cohort, sorted by sample name. Its order is the sample index that
    // CNVContigPloidy and CNVGermlineCaller assign, and that CNVPostprocess
    // asks for -- so every step must be handed the same list.
    cohort = CNVCollectReadCounts.out.counts
        .toSortedList { a, b -> a[0] <=> b[0] }
        .filter { samples -> samples.size() >= 2 }
    cohort_counts = cohort.map { samples -> samples.collect { t -> t[1] } }

    CNVCollectReadCounts.out.counts.count().subscribe { n ->
        if (n == 0)
            log.warn "--cnv: no sample was read-counted, so no CNVs are called."
        else if (n < 2)
            log.warn "--cnv: only ${n} sample was read-counted; gCNV's cohort mode needs several, so no CNVs are called."
        else if (n < 30)
            log.warn ("--cnv: the CNV cohort has only ${n} samples. gCNV learns coverage biases from the cohort " +
                      "itself and is most reliable with 30 or more; expect noisier calls.")
    }

    CNVFilterIntervals(bins, annotated, cohort_counts)
    ploidy = CNVContigPloidy(CNVFilterIntervals.out.filtered, cohort_counts, priors_ch)

    // shard_0001.interval_list -> [1, shard_0001.interval_list]
    shards = CNVFilterIntervals.out.shards
        .flatten()
        .map { f -> tuple(f.baseName.tokenize('_')[1] as Integer, f) }
    CNVGermlineCaller(shards, annotated, cohort_counts, ploidy.calls)

    // PostprocessGermlineCNVCalls needs every shard, in genomic order.
    shard_results = CNVGermlineCaller.out.toSortedList { a, b -> a[0] <=> b[0] }
    calls_shards  = shard_results.map { results -> results.collect { t -> t[1] } }
    model_shards  = shard_results.map { results -> results.collect { t -> t[2] } }

    sample_index = cohort.flatMap { samples ->
        (0..<samples.size()).collect { i -> tuple(samples[i][0], i) }
    }
    CNVPostprocess(sample_index, calls_shards, model_shards, ploidy.calls, gatk_index)

    summary_script = channel.value(file("${projectDir}/modules/r_cnv_summary.R"))
    CNVSummary(
        CNVPostprocess.out.calls.map { _sample_id, intervals, segments, ratios -> [intervals, segments, ratios] }.collect(),
        ploidy.calls,
        fai_index,
        annotation_ch,
        summary_script)

    emit:
    counts_done = CNVCollectReadCounts.out.counts.count()
    summary     = CNVSummary.out.segments
}
