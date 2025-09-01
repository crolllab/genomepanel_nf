#!/usr/bin/env nextflow

params.outdir = "./nf_output/"
params.reference = ""
params.reads = ""
params.SRA_index = ""
params.ploidy = ""
params.max_concurrent = 10


include { variant_calling } from './workflows/variant_calling_wf'

log.info """

   ===========================================
   || GENOME PANEL VARIANT CALLING WORKFLOW ||
   ===========================================

    Steps:
     1. Fastp filtering
     2. BWA alignment
     3. GATK HaplotypeCaller
     4. GATK VariantFiltration
     5. Variant quality plotting
     6. PLINK IBS/PCA analyses   
   
   Configuration:
     outdir       : ${params.outdir}
     reference    : ${params.reference}
     local fastq  : ${params.reads}
     SRA ids      : ${params.SRA_index}
     ploidy       : ${params.ploidy}
    """


workflow {
   variant_calling()
}
