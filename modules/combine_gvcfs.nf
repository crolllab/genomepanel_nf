process CombineGVCFs {
    tag "GATK4 Combine GVCFs"
    cpus 1
    memory '16GB'

    input:
    path gvcf_ch
    val chr
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    path "combined.${chr}.g.vcf.gz*"

    script:
    """
    printf "${gvcf_ch}" > file
    sed 's/ /\\n/g' file > gvcfs.list.tmp
    grep -v "tbi" gvcfs.list.tmp > gvcfs.list

    gatk --java-options "-Xmx4g" \
        CombineGVCFs \
        -R $reference \
        -L $chr \
        -V gvcfs.list \
        -output combined.${chr}.g.vcf.gz
    """
}
