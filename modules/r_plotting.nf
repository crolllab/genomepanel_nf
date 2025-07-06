process RQualPlotting {
    tag "Quality plotting with R"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
    publishDir params.outdir, mode: 'copy'

    input:
    path R_script
    path concat_vcf
 
    output:
    path "final_variants.*.pdf"

    script:

    """   
    R --vanilla < "${R_script}"
    """
}
