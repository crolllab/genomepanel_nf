process PlinkPCA {
    tag "PLINK2 PCA"
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/9_plink", mode: 'copy'

    input:
    path popgen_vcf

    output:
    path "popgen_pca.eigenvec"
    path "popgen_pca.eigenval"
    path "popgen_pca.log"

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
        --out popgen_pca_freq

    # --pca imputes allele frequencies from the samples themselves only when at
    # least 50 are present; passing them via --read-freq keeps smaller panels working.
    # PC count cannot reach the sample count, so cap it.
    n_samples=\$(zcat ${popgen_vcf} | grep -m1 '^#CHROM' | awk '{print NF-9}')
    n_pcs=\$(( n_samples - 1 ))
    if [ "\${n_pcs}" -gt 10 ]; then
        n_pcs=10
    fi
    if [ "\${n_pcs}" -lt 1 ]; then
        echo "ERROR: PCA requires at least 2 samples, found \${n_samples}." >&2
        exit 1
    fi

    plink2 \
        --vcf ${popgen_vcf} \
        --allow-extra-chr \
        --set-all-var-ids @:# \
        --read-freq popgen_pca_freq.afreq \
        --pca \${n_pcs} \
        --out popgen_pca
    """
}
