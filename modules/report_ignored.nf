// Report samples that were silently dropped during the run.
//
// Every per-sample step from download to duplicate marking (SRAdownloadPE/SE,
// trimSequencesPE/SE, bwaMap, samtoolsSort, addRG, mergeRunBAMs, dupRemoval,
// and for PacBio HiFi runs SRAdownloadHiFi, pbmm2Map, hifiFlagstat)
// falls back to an 'ignore' error strategy once its retries are exhausted: the
// task fails, Nextflow carries on, and the sample simply never appears in any
// downstream channel. Without
// this report a run finishes green while samples are quietly missing from the
// final VCF, which is easy to overlook on a panel of a few hundred.
//
// Each input is a collected list of sample IDs, guarded with .ifEmpty([]) in the
// workflow so this process still runs when a stage produced nothing at all.
// The differences are taken here rather than with channel operators, which
// flatten nested lists in ways that are easy to get subtly wrong.
process ReportIgnoredSamples {
    tag "Ignored sample report"
    publishDir "${params.outdir}/1_sra_downloads", mode: 'copy', overwrite: true
    errorStrategy 'retry'
    maxRetries 6

    input:
    val resolved_accessions
    val downloaded_accessions
    val entered_trimming
    val finished_trimming         // run IDs ready for mapping: trimmed Illumina runs, and HiFi runs (never trimmed)
    val finished_read_groups      // run IDs that made it through addRG (Illumina) or hifiFlagstat (HiFi)
    val expected_samples          // sample names those runs resolve to
    val finished_dedup            // sample names that made it through dupRemoval

    output:
    path "ignored_samples.txt", emit: report

    script:
    def dropped_dl   = ((resolved_accessions as List) - (downloaded_accessions as List)).unique().sort()
    def dropped_trim = ((entered_trimming    as List) - (finished_trimming    as List)).unique().sort()
    // Runs that were trimmed but never came out of bwaMap -> samtoolsSort -> addRG
    def dropped_map  = ((finished_trimming   as List) - (finished_read_groups as List)).unique().sort()
    // Samples with at least one read-grouped run that never came out of
    // mergeRunBAMs -> dupRemoval
    def dropped_dup  = ((expected_samples    as List) - (finished_dedup       as List)).unique().sort()
    def total        = dropped_dl.size() + dropped_trim.size() + dropped_map.size() + dropped_dup.size()

    def lines = []
    lines << "# genomepanel_nf - samples dropped before variant calling"
    lines << "# Generated: ${new Date().format('yyyy-MM-dd HH:mm')}"
    lines << "#"
    lines << "# These samples failed a step that is configured to give up rather than"
    lines << "# abort the whole run, so they are absent from the final VCF even though"
    lines << "# the run itself is reported as successful."
    lines << "#"
    lines << "# Total dropped: ${total}"
    lines << ""

    lines << "## Failed to download (${dropped_dl.size()})"
    lines << "# Accession was resolved by SRAresolve, but SRAdownloadPE/SE/HiFi exhausted"
    lines << "# its retries. Re-run to try again, or fetch the reads manually and pass"
    lines << "# them with --reads (or --hifi_reads)."
    if (dropped_dl) {
        dropped_dl.each { d -> lines << d }
    } else {
        lines << "# (none)"
    }
    lines << ""

    lines << "## Failed during read trimming (${dropped_trim.size()})"
    lines << "# Reads were available but trimSequencesPE/SE exhausted its retries."
    lines << "# Usually a truncated or corrupt FASTQ, or an out-of-memory kill."
    if (dropped_trim) {
        dropped_trim.each { t -> lines << t }
    } else {
        lines << "# (none)"
    }
    lines << ""

    lines << "## Failed during mapping (${dropped_map.size()})"
    lines << "# Run IDs. bwaMap, samtoolsSort or addRG (pbmm2Map or hifiFlagstat for"
    lines << "# PacBio HiFi runs) exhausted its retries. If the"
    lines << "# sample has other runs (--SRR_sample_map), it is still called, from fewer"
    lines << "# reads; otherwise it is absent from the final VCF."
    if (dropped_map) {
        dropped_map.each { m -> lines << m }
    } else {
        lines << "# (none)"
    }
    lines << ""

    lines << "## Failed during duplicate marking (${dropped_dup.size()})"
    lines << "# Sample names. mergeRunBAMs or dupRemoval exhausted its retries."
    if (dropped_dup) {
        dropped_dup.each { d -> lines << d }
    } else {
        lines << "# (none)"
    }

    def body = lines.join('\n')
    """
    cat > ignored_samples.txt <<'GENOMEPANEL_IGNORED_EOF'
${body}
GENOMEPANEL_IGNORED_EOF

    echo "Recorded ${total} dropped sample(s) in ignored_samples.txt"
    """
}
