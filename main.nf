#!/usr/bin/env nextflow

params.outdir = "./nf_output/"
params.workdir = "./work"
params.reference = ""
params.reads = ""
params.SRA_index = ""
params.ploidy = ""
params.NCBI_API_key = ""
params.keep_bam = false  // Keep per-sample BAM files
params.keep_gvcf = false  // Keep per-sample GVCF files
params.bwa_index = ""  // Optional: path to pre-built BWA index files
params.min_contig_length = false  // Filter reference contigs shorter than this value (bp)
params.reference_segments = 0  // Genome segment size for parallel variant calling (bp)
params.call_invar_sites = false  // Call invariant sites with GATK HaplotypeCaller
params.bam_input = ""  // Optional: path to pre-existing BAM files
params.SRR_sample_map = ""  // Optional: TSV file mapping SRR IDs to sample names

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
       NCBI API key   : ${params.NCBI_API_key}
       Ploidy         : ${params.ploidy}
       Inv. site calls: ${params.call_invar_sites}
  
       Reference      : ${params.reference}
       Ref segments   : ${params.reference_segments}
       Min contig len : ${params.min_contig_length}
       BWA index      : ${params.bwa_index}
  
     Input data
       Local fastq    : ${params.reads}
       SRA ID file    : ${params.SRA_index}
       SRR-sample map : ${params.SRR_sample_map}
       Local bam      : ${params.bam_input}
  
     Output options
      Working dir    : ${workflow.workDir}
       Output dir     : ${params.outdir}
       Keep BAM       : ${params.keep_bam}
       Keep GVCF      : ${params.keep_gvcf}
    """


workflow {
   variant_calling()
}
