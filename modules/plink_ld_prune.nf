process PlinkLDPrune {
    tag "PLINK2 LD pruning"
    errorStrategy 'retry'
    maxRetries 6
    publishDir "${params.outdir}/9_plink", mode: 'copy'

    input:
    path popgen_vcf

    output:
    path "popgen_ld_pruned.prune.in"
    path "popgen_ld_pruned.prune.out"
    path "popgen_ld_pruned.vcf.gz"
    path "popgen_ld_pruned.log"

    script:
    """
    set -e

    # --bad-ld permits LD estimation on panels of fewer than 50 samples, where r2
    # estimates are unreliable but a hard failure at the end of a multi-day run is
    # worse. It has no effect on larger panels.
    plink2 \
        --vcf ${popgen_vcf} \
        --allow-extra-chr \
        --set-all-var-ids @:# \
        --indep-pairwise 50 5 0.5 \
        --bad-ld \
        --out popgen_ld_pruned

    # The pruned VCF is subset from the input rather than exported by plink2, whose
    # VCF writer diploidises haploid genotypes (1 becomes 1/1) and keeps only GT.
    zcat ${popgen_vcf} | awk -v keep=popgen_ld_pruned.prune.in '
        BEGIN { while ((getline id < keep) > 0) retain[id] = 1 }
        /^#/ { print; next }
        (\$1 ":" \$2) in retain { print }
    ' | gzip -c > popgen_ld_pruned.vcf.gz
    """
}
