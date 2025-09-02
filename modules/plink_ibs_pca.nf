process PLINKIBSPCA {
    tag "PLINK IBS + PCA calculation"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
    publishDir params.outdir, mode: 'copy'

    input:
    path concat_clean_vcf
 
    output:
    tuple path("final_variants.clean.PLINK.eigenvec"), \
          path("final_variants.clean.PLINK.afreq"), \
          path("final_variants.clean.PLINK.king"), \
          path("final_variants.clean.PLINK.bed"), \
          path("final_variants.clean.PLINK.bim"), \
          path("final_variants.clean.PLINK.fam")

    script:

    """   
    plink2 --vcf ${concat_clean_vcf} --keep-allele-order --set-missing-var-ids @:#  --make-bed --out final_variants.clean.PLINK --max-alleles 2
    plink2 --bfile final_variants.clean.PLINK  --freq --out final_variants.clean.PLINK
    plink2 --read-freq final_variants.clean.PLINK.afreq --pca 10 --bfile final_variants.clean.PLINK
    plink2 --bfile final_variants.clean.PLINK --make-king square0 --maf 0.1 --out final_variants.clean.PLINK
    """
}

