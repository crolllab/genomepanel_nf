process GenomicsDBImport {
    tag "GATK4 GenomicsDB Import"
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'ignore' }
    maxRetries 6

    input:
    tuple val(chr), val(interval), path(gvcf_files)
    path reference
    path "${reference}.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), val(interval), path("genomicsdb_${interval.replaceAll('[:\\-]', '_')}", type: 'dir')

    script:
    def interval_safe = interval.replaceAll('[:\\-]', '_')
    def db_path = "genomicsdb_${interval_safe}"
    def batch_size = params.genomicsdb_batch_size ?: 50
    def avail_mem = (task.memory.mega * 0.8).intValue()
    """
    mkdir -p ./gatk_tmp

    # Build sample-name map (samplename TAB absolute_gvcf_path)
    # Read sample name from each gVCF header to preserve RGSM-based naming
    # set by upstream BAM read groups (e.g. from --SRR_sample_map).
    for f in ${gvcf_files}; do
        if [[ "\$f" == *.g.vcf.gz ]]; then
            sample=\$(gzip -cd "\$f" | awk -F'\t' '/^#CHROM/{print \$10; exit}')

            # Fallback to filename-based extraction only if header parsing fails.
            if [ -z "\$sample" ]; then
                base=\$(basename "\$f" .g.vcf.gz)
                sample=\${base%_${interval_safe}}
                echo "WARNING: Could not parse sample from gVCF header for \$f; using filename-derived sample '\$sample'" >&2
            fi

            echo -e "\${sample}\t\$(readlink -f "\$f")" >> sample_map.txt
        fi
    done

    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData --enable-native-access=ALL-UNNAMED" \
        GenomicsDBImport \
        --tmp-dir ./gatk_tmp \
        --sample-name-map sample_map.txt \
        --genomicsdb-workspace-path ${db_path} \
        --overwrite-existing-genomicsdb-workspace \
        -L "${interval}" \
        --batch-size ${batch_size} \
        --reader-threads 2
    """
}
