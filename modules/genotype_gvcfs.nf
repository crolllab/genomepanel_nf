process GenotypeGVCFs {
    tag "GATK4 Genotype GVCFs"
    cpus 1
    memory { 16.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 2


    input:
    tuple val(chr), val(interval), path(cgvcf)
    path reference
    path "${reference.baseName}.fasta.fai"
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
    gatk --java-options "-Xmx16g" GenotypeGVCFs \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V \${combined_file} \
        -output \${output_file}
    
    # Delete the combined GVCF (resolve symlink to actual file)
    cgvcf_target="\$(readlink -f "\${combined_file}")"
    [ -n "\$cgvcf_target" ] && [ -f "\$cgvcf_target" ] && rm "\$cgvcf_target" || true
    """
}
