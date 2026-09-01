process PlinkRelationships {
    tag "PLINK2 relationship matrices"
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/9_plink", mode: 'copy'

    input:
    path popgen_vcf

    output:
    path "popgen_relationships.rel"
    path "popgen_relationships.rel.id"
    path "popgen_relationships.king"
    path "popgen_relationships.king.id"
    path "popgen_relationships.log"

    script:
    """
    set -e

    # Variant IDs in the pipeline VCF are all '.', which --read-freq rejects as
    # duplicates, so assign chrom:pos IDs on import.
    plink2 \
        --vcf ${popgen_vcf} \
        --allow-extra-chr \
        --set-all-var-ids @:# \
        --freq \
        --out popgen_relationships_freq

    # --make-rel imputes allele frequencies from the samples themselves only when at
    # least 50 are present; passing them via --read-freq keeps smaller panels working.
    # --make-king derives its own estimates and is unaffected by their presence.
    plink2 \
        --vcf ${popgen_vcf} \
        --allow-extra-chr \
        --set-all-var-ids @:# \
        --read-freq popgen_relationships_freq.afreq \
        --make-rel square \
        --make-king square \
        --out popgen_relationships
    """
}
