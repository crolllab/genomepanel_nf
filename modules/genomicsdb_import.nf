process GenomicsDBImport {
    tag "GATK4 GenomicsDB Import"
    errorStrategy 'retry'
    maxRetries 3

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
    # Extract sample name by stripping the _<interval_safe>.g.vcf.gz suffix
    for f in ${gvcf_files}; do
        if [[ "\$f" == *.g.vcf.gz ]]; then
            base=\$(basename "\$f" .g.vcf.gz)
            sample=\${base%_${interval_safe}}
            echo -e "\${sample}\\t\$(readlink -f \$f)" >> sample_map.txt
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
