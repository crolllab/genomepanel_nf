process GenotypeGVCFs {
    tag "GATK4 Genotype GVCFs"
    errorStrategy 'retry'
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
    """
    mkdir -p ./gatk_tmp

    output_file="genotyped.${interval_safe}.vcf.gz"

    # Add options for invariant sites if enabled
    if [ "${params.call_invar_sites}" = "true" ]; then
        INVAR_OPTS="--include-non-variant-sites"
    else
        INVAR_OPTS=""
    fi

    gatk --java-options "-Xmx${task.memory.toGiga()-2}g -XX:-UsePerfData --enable-native-access=ALL-UNNAMED" GenotypeGVCFs \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V gendb://${db_dir} \
        \${INVAR_OPTS} \
        -output \${output_file}
    """
}
