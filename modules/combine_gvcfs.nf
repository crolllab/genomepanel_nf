process CombineGVCFs {
    tag "GATK4 Combine GVCFs"
    cpus 1
    memory { 48.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 2

    input:
    tuple val(chr), path(gvcf_files)
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), path("combined.${chr}.g.vcf.gz*")

    script:
    """
    mkdir -p ./gatk_tmp
    
    # Create list of GVCF files (filter out .tbi index files)
    for f in ${gvcf_files}; do
        if [[ "\$f" == *.g.vcf.gz ]]; then
            echo "\$f" >> gvcfs.list
        fi
    done

    gatk --java-options "-Xmx48g" \
        CombineGVCFs \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -L $chr \
        -V gvcfs.list \
        -output combined.${chr}.g.vcf.gz
    """
}
