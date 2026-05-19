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
params.genomicsdb_batch_size = 50   // GenomicsDBImport batch size (samples per batch). 50 is the Broad production default; ~20 MB/sample in heap, so 50 costs ~1 GB leaving ~2.5 GB for TileDB buffers within the default 8 GB process memory.
params.bam_input = ""  // Optional: path to pre-existing BAM files
params.SRR_sample_map = ""  // Optional: TSV file mapping SRR IDs to sample names
params.slurm_queue = ""  // Required when using -profile slurm: SLURM partition name

include { gp_wf } from './workflows/gp_wf'


workflow {

   // ---------------------
   // Validate parameters — catch unknown CLI options before running
   // ---------------------
   def knownParams = [
       'outdir', 'workdir', 'reference', 'reads', 'SRA_index', 'ploidy',
       'NCBI_API_key', 'keep_bam', 'keep_gvcf', 'bwa_index', 'min_contig_length',
       'reference_segments', 'call_invar_sites', 'genomicsdb_batch_size',
       'bam_input', 'SRR_sample_map', 'slurm_queue'
   ] as Set

   def unknownParams = params.keySet() - knownParams
   if (unknownParams) {
       error """\n    ERROR: Unknown parameter(s) supplied: ${unknownParams.sort().join(', ')}\n\n    Valid parameters are:\n        ${knownParams.sort().join('\n        ')}\n\n    Check for typos in your nextflow run command.\n    """
   }

   if (workflow.profile.tokenize(',').contains('slurm') && !params.slurm_queue) {
       error """\n    ERROR: --slurm_queue is required when using -profile slurm.\n    Specify the SLURM partition name on your cluster, e.g.:\n        --slurm_queue long\n    The partition should allow a maximum walltime of at least 7 days for large\n    datasets. Shorter limits (1-2 days) may still work for smaller genomes\n    or low-depth sequencing, but jobs exceeding the partition limit will fail.\n    """
   }

   log.info """
   =============================================
   || GENOMEPANEL_NF VARIANT CALLING WORKFLOW ||
   =============================================

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

   SLURM
       Queue          : ${params.slurm_queue ?: '(not set — not using SLURM)'}
    """
   gp_wf()
}
