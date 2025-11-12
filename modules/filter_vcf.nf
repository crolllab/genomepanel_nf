process FilterVCFs {
    tag "GATK apply VCF filter flags"
    cpus 1
    memory '16GB'

    input:
    tuple val(chr), path(vcf_ch)
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), path("filtered.${chr}.vcf.gz")

    script:
    def QD=20.0
    def MQ=30.0
    def ReadPosRankSum_lower=-2.0
    def ReadPosRankSum_upper=2.0
    def MQRankSum_lower=-2.0
    def MQRankSum_upper=2.0
    def BaseQRankSum_lower=-2.0
    def BaseQRankSum_upper=2.0

    """
    mkdir -p ./gatk_tmp
       
    gatk IndexFeatureFile -I genotyped.${chr}.vcf.gz
    gatk --java-options "-Xmx4g" VariantFiltration \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V genotyped.${chr}.vcf.gz \
        -output filtered.${chr}.vcf.gz \
        --filter 'QD < $QD' --filter-name 'QDFilter' \
        --filter 'MQ < $MQ' --filter-name 'MQ' \
        --filter 'ReadPosRankSum < $ReadPosRankSum_lower' --filter-name 'ReadPosRankSum' \
        --filter 'ReadPosRankSum > $ReadPosRankSum_upper' --filter-name 'ReadPosRankSum' \
        --filter 'MQRankSum < $MQRankSum_lower' --filter-name 'MQRankSum' \
        --filter 'MQRankSum > $MQRankSum_upper' --filter-name 'MQRankSum' \
        --filter 'BaseQRankSum < $BaseQRankSum_lower' --filter-name 'BaseQRankSum' \
        --filter 'BaseQRankSum > $BaseQRankSum_upper' --filter-name 'BaseQRankSum'
    """
}
