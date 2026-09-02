// Report samples that were silently dropped during the run.
//
// SRAdownloadPE/SE and trimSequencesPE/SE fall back to an 'ignore' error
// strategy once their retries are exhausted: the task fails, Nextflow carries
// on, and the sample simply never appears in any downstream channel. Without
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
    val finished_trimming

    output:
    path "ignored_samples.txt", emit: report

    script:
    def dropped_dl   = ((resolved_accessions as List) - (downloaded_accessions as List)).unique().sort()
    def dropped_trim = ((entered_trimming    as List) - (finished_trimming    as List)).unique().sort()
    def total        = dropped_dl.size() + dropped_trim.size()

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
    lines << "# Accession was resolved by SRAresolve, but SRAdownloadPE/SE exhausted"
    lines << "# its retries. Re-run to try again, or fetch the reads manually and pass"
    lines << "# them with --reads."
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

    def body = lines.join('\n')
    """
    cat > ignored_samples.txt <<'GENOMEPANEL_IGNORED_EOF'
${body}
GENOMEPANEL_IGNORED_EOF

    echo "Recorded ${total} dropped sample(s) in ignored_samples.txt"
    """
}
