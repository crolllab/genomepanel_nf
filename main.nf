#!/usr/bin/env nextflow

params.outdir = "./nf_output/"
params.reference = ""
params.reads = ""
params.SRA_index = ""
params.ploidy = ""
params.NCBI_API_key = ""
params.keep_bam = false  // Keep per-sample BAM files
params.keep_gvcf = false  // Keep per-sample GVCF files
params.bwa_index = ""  // Optional: path to pre-built BWA index files
params.min_contig_length = false  // Filter reference contigs shorter than this value (bp)
params.reference_segments = 1000000  // Genome segment size for parallel variant calling (bp)
params.call_invar_sites = false  // Call invariant sites with GATK HaplotypeCaller

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
     min contig len : ${params.min_contig_length}
     ref segments   : ${params.reference_segments}
     invar sites    : ${params.call_invar_sites}

     local files    : ${params.reads}
     SRA ids file   : ${params.SRA_index}

     outdir         : ${params.outdir}
     keep BAM       : ${params.keep_bam}
     keep GVCF      : ${params.keep_gvcf}
    """


workflow {
   variant_calling()
}
