process RQualPlotting {
    tag "Plotting with R"
    errorStrategy 'ignore'
    cpus 1
    memory '16GB'
    publishDir "${params.outdir}/qual_plots", mode: 'copy'

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
