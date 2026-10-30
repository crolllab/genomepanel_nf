// =============================================================================
//  Germline copy-number variant calling with GATK gCNV (--cnv)
// =============================================================================
//  The cohort-mode gCNV workflow, with the panel itself as the cohort:
//
//    CNVPreprocessIntervals (once)  -- reference cut into --cnv_bin_length bins
//    CNVAnnotateIntervals   (once)  -- GC content per bin
//    CNVCollectReadCounts   (per sample)
//    CNVFilterIntervals     (once)  -- drop GC-extreme, empty and outlier bins,
//                                      then split the rest into shards
//    CNVContigPloidy        (once)  -- per-sample, per-contig ploidy
//    CNVGermlineCaller      (per shard of --cnv_shard_bins bins)
//    CNVPostprocess         (per sample) -- per-bin and per-segment VCFs
//
//  Only the per-sample read counting touches the BAMs, so gp_wf.nf holds the
//  BAM cleanup back until every CNVCollectReadCounts task has finished.
//
//  The steps from CNVContigPloidy on run GATK's Python model (gcnvkernel),
//  which the biocontainers GATK image does not ship; every CNV step runs in
//  the Broad image instead (see nextflow.config), so the whole CNV toolchain
//  is one GATK build. gcnvkernel compiles its model with PyTensor (Theano's
//  successor), which caches the compiled code under ~/.pytensor by default:
//  that fails outright where the container sees the home directory read-only,
//  and otherwise makes parallel tasks queue on the cache's lock, so each of
//  those tasks keeps its own cache in its work directory.
//
//  The steps that run once for the whole cohort retry only on out-of-memory
//  exits, with memory stepping up per attempt (see nextflow.config); an OOM
//  kill that GATK or its Python model reports with another status is mapped
//  to 247, as in GenomicsDBImport. Any other failure recurs identically on a
//  retry, so it stops the run.
//
//  Extra GATK arguments can be added per step through `ext.args` in a custom
//  config, e.g. withName:CNVGermlineCaller { ext.args = '--p-alt 1e-4' }.
//  An option set there replaces the pipeline's own value for it (see
//  withDefaults below).
// =============================================================================

// The pipeline's GermlineCNVCaller settings: the GATK-SV whole-genome model
// (no bias factors, a tightly held per-bin mean bias, near-zero prior on
// copy-number changes outside CNV-active bins), with the unexplained variance
// held at 1e-4 instead of GATK's 1e-2 and CNV-active bins made rarer a priori.
// GATK's defaults let the per-bin variance grow until a deletion shared by
// many samples counts as noise, and its bias factors learn such a deletion as
// a coverage bias: on a 434-isolate haploid panel they called none of 247
// isolates lacking MAT1-2-1 deleted, and only ~10% of bins deleted in half
// the panel. These settings called all 247 and ~95% of those bins, without
// false deletions and with gains matching the coverage (see "Model settings"
// in docs/configuration.md). The coherence lengths follow the bin
// length, so a CNV can be as short as one bin.
def gcnvCallerDefaults() {
    [
        'interval-psi-scale'                    : '1e-4',
        'sample-psi-scale'                      : '1e-4',
        'p-active'                              : '0.01',
        'p-alt'                                 : '1e-6',
        'class-coherence-length'                : "${params.cnv_bin_length}",
        'cnv-coherence-length'                  : "${params.cnv_bin_length}",
        'enable-bias-factors'                   : 'false',
        'log-mean-bias-standard-deviation'      : '0.01',
        'copy-number-posterior-expectation-mode': 'EXACT',
        'caller-update-convergence-threshold'   : '1e-6',
        'learning-rate'                         : '0.03',
        'convergence-snr-trigger-threshold'     : '0.2',
        'convergence-snr-averaging-window'      : '100'
    ]
}

// The pipeline's options plus the user's ext.args. GATK refuses an option
// given twice, so an option that ext.args sets drops the pipeline's value.
def withDefaults(Map defaults, extra) {
    def args  = extra ? extra.toString() : ''
    def given = (args =~ /--([A-Za-z0-9-]+)/).collect { m -> m[1] } as Set
    def kept  = defaults.findAll { k, _v -> !(k in given) }.collect { k, v -> "--${k} ${v}" }
    return (kept + (args ? [args] : [])).join(' ')
}

// Whole-genome bins. --padding 0 and OVERLAPPING_ONLY are the WGS settings:
// padding is for exome targets, and the default merging rule (ALL) would fuse
// the abutting bins straight back into whole contigs.
process CNVPreprocessIntervals {
    tag "CNV: binning the reference"
    errorStrategy 'retry'
    maxRetries 6

    input:
    path reference
    path "${reference}.fai"
    path "${reference.baseName}.dict"
    path exclude_intervals   // [] without --cnv_exclude_intervals

    output:
    path "bins.interval_list"

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    def exclude = exclude_intervals ? "--exclude-intervals ${exclude_intervals}" : ""
    """
    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData" PreprocessIntervals \\
        --tmp-dir . \\
        -R ${reference} \\
        --bin-length ${params.cnv_bin_length} \\
        --padding 0 \\
        --interval-merging-rule OVERLAPPING_ONLY \\
        ${exclude} \\
        -O bins.interval_list
    """
}

process CNVAnnotateIntervals {
    tag "CNV: GC content per bin"
    errorStrategy 'retry'
    maxRetries 6

    input:
    path reference
    path "${reference}.fai"
    path "${reference.baseName}.dict"
    path bins

    output:
    path "annotated_intervals.tsv"

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    """
    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData" AnnotateIntervals \\
        --tmp-dir . \\
        -R ${reference} \\
        -L ${bins} \\
        --interval-merging-rule OVERLAPPING_ONLY \\
        -O annotated_intervals.tsv
    """
}

process CNVCollectReadCounts {
    tag "CNV: read counts ${sample_id}"
    // Per-sample step: once retries run out the sample is left out of the CNV
    // cohort (Nextflow reports the ignored task) instead of stopping the run.
    errorStrategy { task.attempt <= 6 ? 'retry' : 'ignore' }
    maxRetries 6

    input:
    path reference
    path "${reference}.fai"
    path "${reference.baseName}.dict"
    path bins
    tuple val(sample_id), path(bam), path(bai)

    output:
    tuple val(sample_id), path("${sample_id}.counts.hdf5"), emit: counts

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    // Count duplicate-flagged reads only when HaplotypeCaller uses them too
    // (--use_duplicate_reads), so both halves of the pipeline see the same reads.
    def dup_filter = params.use_duplicate_reads ? "--disable-read-filter NotDuplicateReadFilter" : ""
    """
    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData" CollectReadCounts \\
        --tmp-dir . \\
        -R ${reference} \\
        -I ${bam} \\
        -L ${bins} \\
        --interval-merging-rule OVERLAPPING_ONLY \\
        --minimum-mapping-quality ${params.cnv_min_mapq} \\
        ${dup_filter} \\
        --format HDF5 \\
        -O ${sample_id}.counts.hdf5
    """
}

// Bin filtering uses the whole cohort's counts, so it runs once all samples
// are counted. The bins that survive are split into shards of
// --cnv_shard_bins here as well, rather than in a task of their own.
//
// GATK's low-count filter drops bins with fewer than 10 reads in more than
// 50% of samples -- every deletion carried by most of the panel. The pipeline
// drops them only past 90%: beyond that too few samples show the bin's
// normal coverage for a deletion to be called against it.
process CNVFilterIntervals {
    tag "CNV: filtering bins"
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'finish' }
    maxRetries 6

    input:
    path bins
    path annotated_intervals
    path counts

    output:
    path "filtered.interval_list", emit: filtered
    path "shard_*.interval_list",  emit: shards

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    def inputs = counts.collect { c -> "-I ${c}" }.join(' ')
    """
    oom_kills() {
        local ev="/sys/fs/cgroup\$(sed -n 's/^0:://p' /proc/self/cgroup)/memory.events"
        if [ -r "\$ev" ]; then awk '\$1 == "oom_kill" { print \$2 }' "\$ev"; else echo 0; fi
    }
    oom_before=\$(oom_kills)

    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData" FilterIntervals \\
        --tmp-dir . \\
        -L ${bins} \\
        --annotated-intervals ${annotated_intervals} \\
        ${inputs} \\
        --interval-merging-rule OVERLAPPING_ONLY \\
        ${withDefaults(['low-count-filter-percentage-of-samples': '90'], task.ext.args)} \\
        -O filtered.interval_list || {
        rc=\$?
        if [ "\$(oom_kills)" -gt "\$oom_before" ]; then
            echo "Exit status \$rc coincides with a cgroup OOM kill; reporting it as 247" >&2
            rc=247
        fi
        exit \$rc
    }

    kept=\$(grep -vc '^@' filtered.interval_list || true)
    total=\$(grep -vc '^@' ${bins} || true)
    echo "FilterIntervals kept \${kept} of \${total} bins"
    if [ "\${kept}" -eq 0 ]; then
        echo "ERROR: FilterIntervals removed every bin, so there is nothing to call CNVs on." >&2
        echo "Usual causes: very low coverage (raise --cnv_bin_length), or a cohort whose" >&2
        echo "coverage is so uneven that every bin is an outlier in most samples." >&2
        exit 1
    fi

    # Shards keep the interval-list header, and bins stay in genomic order:
    # PostprocessGermlineCNVCalls stitches the shards back together in order.
    awk -v n=${params.cnv_shard_bins} '
        /^@/ { header = header \$0 "\\n"; next }
        {
            if (count % n == 0) {
                if (out) close(out)
                out = sprintf("shard_%04d.interval_list", count / n + 1)
                printf "%s", header > out
            }
            print > out
            count++
        }' filtered.interval_list
    """
}

// Per-contig ploidy of every sample. Without --cnv_contig_ploidy_priors the
// priors are built from --ploidy: 0.97 on that ploidy for every contig, the
// rest spread evenly over 0 .. ploidy+1, which still lets a contig that is
// absent from a sample (an accessory chromosome) be called as ploidy 0.
process CNVContigPloidy {
    tag "CNV: contig ploidy"
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'finish' }
    maxRetries 6

    input:
    path filtered
    path counts
    path priors   // [] without --cnv_contig_ploidy_priors

    output:
    path "contig_ploidy-calls", emit: calls
    path "contig_ploidy-model", emit: model

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    def inputs = counts.collect { c -> "-I ${c}" }.join(' ')
    def priors_file = priors ? "${priors}" : "generated_ploidy_priors.tsv"
    """
    export PYTENSOR_FLAGS="base_compiledir=\$PWD/.pytensor"
    export OMP_NUM_THREADS=${task.cpus} MKL_NUM_THREADS=${task.cpus}

    if [ ! -s "${priors_file}" ]; then
        grep -v '^@' ${filtered} | cut -f1 | uniq | awk -v p=${params.ploidy} '
            BEGIN {
                states = p + 2
                other  = 0.03 / (states - 1)
                printf "CONTIG_NAME"
                for (i = 0; i < states; i++) printf "\\tPLOIDY_PRIOR_%d", i
                printf "\\n"
            }
            !seen[\$1]++ {
                printf "%s", \$1
                for (i = 0; i < states; i++) printf "\\t%s", (i == p ? 0.97 : other)
                printf "\\n"
            }' > ${priors_file}
    fi

    oom_kills() {
        local ev="/sys/fs/cgroup\$(sed -n 's/^0:://p' /proc/self/cgroup)/memory.events"
        if [ -r "\$ev" ]; then awk '\$1 == "oom_kill" { print \$2 }' "\$ev"; else echo 0; fi
    }
    oom_before=\$(oom_kills)

    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData" DetermineGermlineContigPloidy \\
        --tmp-dir . \\
        -L ${filtered} \\
        --interval-merging-rule OVERLAPPING_ONLY \\
        --contig-ploidy-priors ${priors_file} \\
        ${inputs} \\
        ${task.ext.args ?: ''} \\
        --output . \\
        --output-prefix contig_ploidy || {
        rc=\$?
        if [ "\$(oom_kills)" -gt "\$oom_before" ]; then
            echo "Exit status \$rc coincides with a cgroup OOM kill; reporting it as 247" >&2
            rc=247
        fi
        exit \$rc
    }
    """
}

process CNVGermlineCaller {
    tag "CNV: calling shard ${shard_index}"
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'finish' }
    maxRetries 6

    input:
    tuple val(shard_index), path(shard)
    path annotated_intervals
    path counts
    path ploidy_calls

    output:
    tuple val(shard_index), path("${shard.baseName}-calls"), path("${shard.baseName}-model")

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    def inputs = counts.collect { c -> "-I ${c}" }.join(' ')
    // GC content goes to the model only with --cnv_gc_correction. With the
    // variance held low, its per-sample GC curves are the one free term left,
    // and in AT-rich regions -- where deletions concentrate in many genomes --
    // they drifted ~5-fold and turned normal coverage into CN5 calls.
    def gc = params.cnv_gc_correction in [true, 'true'] ? "--annotated-intervals ${annotated_intervals}" : ""
    """
    export PYTENSOR_FLAGS="base_compiledir=\$PWD/.pytensor"
    export OMP_NUM_THREADS=${task.cpus} MKL_NUM_THREADS=${task.cpus}

    oom_kills() {
        local ev="/sys/fs/cgroup\$(sed -n 's/^0:://p' /proc/self/cgroup)/memory.events"
        if [ -r "\$ev" ]; then awk '\$1 == "oom_kill" { print \$2 }' "\$ev"; else echo 0; fi
    }
    oom_before=\$(oom_kills)

    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData" GermlineCNVCaller \\
        --tmp-dir . \\
        --run-mode COHORT \\
        -L ${shard} \\
        --interval-merging-rule OVERLAPPING_ONLY \\
        ${gc} \\
        --contig-ploidy-calls ${ploidy_calls} \\
        --max-copy-number ${params.cnv_max_copy_number} \\
        ${inputs} \\
        ${withDefaults(gcnvCallerDefaults(), task.ext.args)} \\
        --output . \\
        --output-prefix ${shard.baseName} || {
        rc=\$?
        if [ "\$(oom_kills)" -gt "\$oom_before" ]; then
            echo "Exit status \$rc coincides with a cgroup OOM kill; reporting it as 247" >&2
            rc=247
        fi
        exit \$rc
    }
    """
}

// sample_index is the sample's position in the cohort as passed to
// CNVContigPloidy and CNVGermlineCaller (sorted by name, see cnv_wf.nf).
// The script checks it against the sample name GATK recorded, so a mix-up
// fails loudly rather than labelling one sample's calls with another's name.
process CNVPostprocess {
    tag "CNV: segmenting ${sample_id}"
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'finish' }
    maxRetries 6
    publishDir "${params.outdir}/11_cnv/samples", mode: 'copy'

    input:
    tuple val(sample_id), val(sample_index)
    path calls_shards    // in genomic order
    path model_shards    // in genomic order
    path ploidy_calls
    path dict

    output:
    tuple val(sample_id),
          path("${sample_id}.cnv_intervals.vcf.gz"),
          path("${sample_id}.cnv_segments.vcf.gz"),
          path("${sample_id}.cnv_denoised_copy_ratios.tsv"),
          emit: calls
    path "${sample_id}.cnv_*.vcf.gz.tbi"

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    def calls_args = calls_shards.collect { d -> "--calls-shard-path ${d}" }.join(' ')
    def model_args = model_shards.collect { d -> "--model-shard-path ${d}" }.join(' ')
    """
    export PYTENSOR_FLAGS="base_compiledir=\$PWD/.pytensor"
    export OMP_NUM_THREADS=${task.cpus} MKL_NUM_THREADS=${task.cpus}

    recorded=\$(cat ${ploidy_calls}/SAMPLE_${sample_index}/sample_name.txt)
    if [ "\${recorded}" != "${sample_id}" ]; then
        echo "ERROR: sample index ${sample_index} is '\${recorded}' in the gCNV calls, expected '${sample_id}'." >&2
        exit 1
    fi

    oom_kills() {
        local ev="/sys/fs/cgroup\$(sed -n 's/^0:://p' /proc/self/cgroup)/memory.events"
        if [ -r "\$ev" ]; then awk '\$1 == "oom_kill" { print \$2 }' "\$ev"; else echo 0; fi
    }
    oom_before=\$(oom_kills)

    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData" PostprocessGermlineCNVCalls \\
        --tmp-dir . \\
        ${calls_args} \\
        ${model_args} \\
        --contig-ploidy-calls ${ploidy_calls} \\
        --sample-index ${sample_index} \\
        --autosomal-ref-copy-number ${params.ploidy} \\
        --sequence-dictionary ${dict} \\
        --output-genotyped-intervals ${sample_id}.cnv_intervals.vcf.gz \\
        --output-genotyped-segments ${sample_id}.cnv_segments.vcf.gz \\
        --output-denoised-copy-ratios ${sample_id}.cnv_denoised_copy_ratios.tsv || {
        rc=\$?
        if [ "\$(oom_kills)" -gt "\$oom_before" ]; then
            echo "Exit status \$rc coincides with a cgroup OOM kill; reporting it as 247" >&2
            rc=247
        fi
        exit \$rc
    }
    """
}
