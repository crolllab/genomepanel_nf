process GenotypeGVCFs {
    tag "GATK4 Genotype GVCFs"
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'ignore' }
    maxRetries 3


    input:
    tuple val(chr), val(interval), path(db_dir)
    path reference
    path "${reference}.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), val(interval), path("genotyped.${interval.replaceAll('[:\\-]', '_')}.vcf.gz")

    script:
    def interval_safe = interval.replaceAll('[:\\-]', '_')
    def avail_mem = (task.memory.mega * 0.8).intValue()
    """
    mkdir -p ./gatk_tmp

    output_file="genotyped.${interval_safe}.vcf.gz"

    # Add options for invariant sites if enabled
    if [ "${params.call_invar_sites}" = "true" ]; then
        INVAR_OPTS="--include-non-variant-sites"
    else
        INVAR_OPTS=""
    fi

    gatk --java-options "-Xmx${avail_mem}m -XX:-UsePerfData --enable-native-access=ALL-UNNAMED" GenotypeGVCFs \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V gendb://${db_dir} \
        \${INVAR_OPTS} \
        -output \${output_file}
    """
}
