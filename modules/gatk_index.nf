process gatkIndex {
    tag "Reference GATK index building"
    cpus 1
    memory '32GB'

    input:
    path reference

    output:
    file "${reference.baseName}.dict"

    script:
    """
    picard CreateSequenceDictionary R=$reference O=${reference.baseName}.dict
    """
}
