process GenotypeGVCFs {
    tag "GATK4 Genotype GVCFs"
    errorStrategy 'retry'
    maxRetries 3


    input:
    tuple val(chr), val(interval), path(cgvcf)
    path reference
    path "${reference}.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), val(interval), path("genotyped.${interval.replaceAll('[:\\-]', '_')}.vcf.gz")

    script:
    def interval_safe = interval.replaceAll('[:\\-]', '_')
    """
    mkdir -p ./gatk_tmp
    
    combined_file="combined.${interval_safe}.g.vcf.gz"
    output_file="genotyped.${interval_safe}.vcf.gz"
       
    gatk IndexFeatureFile -I \${combined_file}
    
    # Add options for invariant sites if enabled
    if [ "${params.call_invar_sites}" = "true" ]; then
        INVAR_OPTS="--include-non-variant-sites"
    else
        INVAR_OPTS=""
    fi
    
    gatk --java-options "-Xmx${task.memory.toGiga()-2}g" GenotypeGVCFs \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V \${combined_file} \
        \${INVAR_OPTS} \
        -output \${output_file}
    
    # Delete the combined GVCF (resolve symlink to actual file)
    cgvcf_target="\$(readlink -f "\${combined_file}")"
    [ -n "\$cgvcf_target" ] && [ -f "\$cgvcf_target" ] && rm "\$cgvcf_target" || true
    """
}
