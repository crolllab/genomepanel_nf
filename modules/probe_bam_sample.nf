process probeBAMSample {
    tag "Reading @RG SM tag: ${orig_id}"
    errorStrategy 'retry'
    maxRetries 6

    input:
    tuple val(orig_id), path(bam), path(bai)

    output:
    tuple val(orig_id), env('SM'), path(bam), path(bai), emit: bam

    script:
    // --bam_input's sample identity comes from the BAM's own @RG SM tag, not
    // the filename: two files named after different runs can carry the same
    // SM (e.g. re-supplying christine's per-run --keep_bam output, where
    // *_RG_dedup.bam is named by run but tagged by sample). Filename-derived
    // naming here would silently treat them as distinct samples and hand
    // GenomicsDBImport duplicate SM entries at the interval level -- the same
    // failure this pipeline hit reading its own BAMs back in.
    """
    SM=\$(samtools view -H ${bam} | awk -F'\t' '
        /^@RG/ {
            for (i = 1; i <= NF; i++) {
                if (\$i ~ /^SM:/) { print substr(\$i, 4); exit }
            }
        }')
    if [ -z "\$SM" ]; then
        echo "ERROR: no @RG SM tag found in ${bam}. --bam_input requires BAMs" >&2
        echo "carrying a read group with a sample (SM) tag -- add one with:" >&2
        echo "  picard AddOrReplaceReadGroups -RGSM <name> ..." >&2
        exit 1
    fi
    """
}
