process FilterVCFs {
    tag "GATK apply VCF filter flags"
    cpus 1
    memory { 16.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 3

    input:
    tuple val(chr), val(interval), path(vcf_ch)
    path reference
    path "${reference.baseName}.fasta.fai"
    path "${reference.baseName}.dict"

    output:
    tuple val(chr), val(interval), path("filtered.${interval.replaceAll('[:\\-]', '_')}.vcf.gz*")

    script:
    def QD=20.0
    def MQ=30.0
    def ReadPosRankSum_lower=-2.0
    def ReadPosRankSum_upper=2.0
    def MQRankSum_lower=-2.0
    def MQRankSum_upper=2.0
    def BaseQRankSum_lower=-2.0
    def BaseQRankSum_upper=2.0

    def interval_safe = interval.replaceAll('[:\\-]', '_')
    """
    mkdir -p ./gatk_tmp
    
    input_file="genotyped.${interval_safe}.vcf.gz"
    output_file="filtered.${interval_safe}.vcf.gz"
       
    gatk IndexFeatureFile -I \${input_file}
    gatk --java-options "-Xmx${task.memory.toGiga()-2}g" VariantFiltration \
        --tmp-dir ./gatk_tmp \
        -R $reference \
        -V \${input_file} \
        -output \${output_file} \
        --filter 'QD < $QD' --filter-name 'QDFilter' \
        --filter 'MQ < $MQ' --filter-name 'MQ' \
        --filter 'ReadPosRankSum < $ReadPosRankSum_lower' --filter-name 'ReadPosRankSum' \
        --filter 'ReadPosRankSum > $ReadPosRankSum_upper' --filter-name 'ReadPosRankSum' \
        --filter 'MQRankSum < $MQRankSum_lower' --filter-name 'MQRankSum' \
        --filter 'MQRankSum > $MQRankSum_upper' --filter-name 'MQRankSum' \
        --filter 'BaseQRankSum < $BaseQRankSum_lower' --filter-name 'BaseQRankSum' \
        --filter 'BaseQRankSum > $BaseQRankSum_upper' --filter-name 'BaseQRankSum'
    
    # Create index for concatenation
    gatk IndexFeatureFile -I \${output_file}
    """
}
