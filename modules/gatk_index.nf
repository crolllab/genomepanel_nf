process gatkIndex {
    time '1d'
    tag "Reference GATK index building"
    cpus 1
    memory { 4.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 3

    input:
    path reference

    output:
    file "${reference.baseName}.dict"

    script:
    """
    picard -Xmx${task.memory.toGiga()-2}g CreateSequenceDictionary R=$reference O=${reference.baseName}.dict
    """
}
