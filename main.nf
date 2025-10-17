#!/usr/bin/env nextflow

params.outdir = "./nf_output/"
params.reference = ""
params.reads = ""
params.SRA_index = ""
params.ploidy = ""
params.NCBI_API_key = ""
params.keep_bam_gvcf = "false"  // or "true"
params.bwa_index = ""  // Optional: path to pre-built BWA index files

include { variant_calling } from './workflows/variant_calling_wf'

log.info """

   ===========================================
   || GENOME PANEL VARIANT CALLING WORKFLOW ||
   ===========================================

    Steps:
     1. SRA query and download
     2. Fastp filtering
     3. BWA alignment
     4. GATK HaplotypeCaller
     5. GATK VariantFiltration
     6. Variant quality plotting, read and mapping stats   
   
   Configuration:
     working dir    : ${params.workdir}
     NCBI API key   : ${params.NCBI_API_key}
     ploidy         : ${params.ploidy}

     reference      : ${params.reference}
     bwa_index      : ${params.bwa_index}

     local files    : ${params.reads}
     SRA ids file   : ${params.SRA_index}

     outdir         : ${params.outdir}
     keep BAM/gvcf  : ${params.keep_bam_gvcf}
    """


workflow {
   variant_calling()
}
