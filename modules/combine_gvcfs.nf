process CombineGVCFs {
    time '7d'
    tag "GATK4 Combine GVCFs"
    cpus 1
    memory { 4.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 3

    input:
    tuple val(chr), val(interval), path(gvcf_files)
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), val(interval), path("combined.${interval.replaceAll('[:\\-]', '_')}.g.vcf.gz*")

    script:
    def interval_safe = interval.replaceAll('[:\\-]', '_')
    """
    mkdir -p ./gatk_tmp
    
    # Create list of GVCF files (filter out .tbi index files)
    for f in ${gvcf_files}; do
        if [[ "\$f" == *.g.vcf.gz ]]; then
            echo "\$f" >> gvcfs.list
        fi
    done

    gatk --java-options "-Xmx${task.memory.toGiga()-2}g" \
        CombineGVCFs \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -L "${interval}" \
        -V gvcfs.list \
        -output combined.${interval_safe}.g.vcf.gz
    """
}
