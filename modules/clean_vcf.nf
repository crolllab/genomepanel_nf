process CleanVCFs {
    tag "Remove low-qual SNPs"
    errorStrategy 'retry'
    maxRetries 3

    input:
    tuple val(chr), val(interval), path(fvcf_ch)
    path reference
    path "${reference}.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), val(interval), path("clean.${interval.replaceAll('[:\\-]', '_')}.vcf.gz*")

    script:
    def interval_safe = interval.replaceAll('[:\\-]', '_')
    """
    mkdir -p ./gatk_tmp
    
    input_file="filtered.${interval_safe}.vcf.gz"
    output_file="clean.${interval_safe}.vcf.gz"
       
    gatk IndexFeatureFile -I \${input_file}
    
    # Conditionally exclude non-variants based on parameter
    if [ "${params.call_invar_sites}" = "true" ]; then
        NON_VAR_OPTS=""
    else
        NON_VAR_OPTS="--exclude-non-variants"
    fi
    
    gatk --java-options "-Xmx${task.memory.toGiga()-2}g -XX:-UsePerfData --enable-native-access=ALL-UNNAMED" SelectVariants \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V \${input_file} \
        -O \${output_file} \
        --exclude-filtered \${NON_VAR_OPTS} --remove-unused-alternates
    
    # Create index for concatenation
    gatk IndexFeatureFile -I \${output_file}
    """
}
