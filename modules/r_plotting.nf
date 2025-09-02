process RQualPlotting {
    tag "Plotting with R"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
    publishDir params.outdir, mode: 'copy'

    input:
    path R_script
    path concat_vcf
    tuple path(eigenvec), path(afreq), path(king), path(bed), path(bim), path(fam)
 
    output:
    path "final_variants.*.pdf"

    script:

    """   
    R --vanilla < "${R_script}"
    """
}
