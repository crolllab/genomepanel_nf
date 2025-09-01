process PLINKIBSPCA {
    tag "PLINK IBS + PCA calculation"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
    publishDir params.outdir, mode: 'copy'

    input:
    path concat_clean_vcf
 
    output:
    path "final_variants.clean.PLINK.*"

    script:

    """   
    plink2 --vcf ${concat_clean_vcf} --make-king square0 --maf 0.1 --out final_variants.clean.PLINK
    plink2 --vcf ${concat_clean_vcf} --pca 10 --out final_variants.clean.PLINK
    """
}
