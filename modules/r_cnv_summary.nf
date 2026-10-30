process CNVSummary {
    tag "CNV: summary tables"
    // Retry only on memory/kill exits (memory scales with the attempt); an R
    // error recurs identically on every retry. An OOM kill reported with
    // another exit status is mapped to 247 below, as in GenomicsDBImport.
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'finish' }
    maxRetries 6
    publishDir "${params.outdir}/11_cnv", mode: 'copy'

    input:
    path sample_calls    // every sample's *.cnv_intervals.vcf.gz, *.cnv_segments.vcf.gz, *.cnv_denoised_copy_ratios.tsv
    path ploidy_calls
    path fai
    path annotation      // [] without --cnv_gene_annotation
    path r_script

    output:
    path "cnv_segments.tsv",        emit: segments
    path "cnv_contig_ploidy.tsv"
    path "cnv_sample_summary.tsv"
    path "cnv_bins.tsv.gz",         optional: true
    path "cnv_genes.tsv",           optional: true
    path "cnv_genes_long.tsv",      optional: true

    script:
    """
    oom_kills() {
        local ev="/sys/fs/cgroup\$(sed -n 's/^0:://p' /proc/self/cgroup)/memory.events"
        if [ -r "\$ev" ]; then awk '\$1 == "oom_kill" { print \$2 }' "\$ev"; else echo 0; fi
    }
    oom_before=\$(oom_kills)

    # Bin-level matrix (--cnv_bin_matrix). Built here by streaming rather than
    # in R: it is bins x samples, which for a large genome at 1 kb bins does
    # not fit in memory. Every sample's intervals VCF lists the same bins in
    # the same (sequence dictionary) order, so the copy-number columns can be
    # pasted side by side.
    if [ "${params.cnv_bin_matrix}" = "true" ]; then
        mkdir -p bin_columns
        first=""
        for vcf in \$(ls *.cnv_intervals.vcf.gz | sort); do
            sample=\$(basename "\$vcf" .cnv_intervals.vcf.gz)
            [ -z "\$first" ] && first="\$vcf"
            zcat "\$vcf" | awk -F'\\t' -v s="\$sample" '
                /^##/ { next }
                /^#CHROM/ { print s; next }
                {
                    if (!cn) { n = split(\$9, f, ":"); for (i = 1; i <= n; i++) if (f[i] == "CN") cn = i }
                    split(\$10, v, ":"); print v[cn]
                }' > "bin_columns/\$sample"
        done
        zcat "\$first" | awk -F'\\t' '
            /^##/ { next }
            /^#CHROM/ { print "contig\\tstart\\tend"; next }
            { match(\$8, /END=[0-9]+/); print \$1 "\\t" \$2 "\\t" substr(\$8, RSTART + 4, RLENGTH - 4) }' > bin_matrix.tsv
        # Paste in batches, so a large panel never needs thousands of open files.
        ls bin_columns | sort | split -l 500 - batch_
        for batch in batch_*; do
            paste bin_matrix.tsv \$(sed 's|^|bin_columns/|' "\$batch") > bin_matrix.tmp
            mv bin_matrix.tmp bin_matrix.tsv
        done
        gzip -c bin_matrix.tsv > cnv_bins.tsv.gz
        rm -rf bin_columns batch_* bin_matrix.tsv
    fi

    Rscript ${r_script} \\
        --fai ${fai} \\
        --ploidy-calls ${ploidy_calls} \\
        --ref-copy-number ${params.ploidy} \\
        --min-qs ${params.cnv_min_qs} \\
        --annotation "${annotation}" \\
        --gene-feature "${params.cnv_gene_feature}" || {
        rc=\$?
        if [ "\$(oom_kills)" -gt "\$oom_before" ]; then
            echo "Exit status \$rc coincides with a cgroup OOM kill; reporting it as 247" >&2
            rc=247
        fi
        exit \$rc
    }
    """
}
