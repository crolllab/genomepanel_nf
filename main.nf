#!/usr/bin/env nextflow

params.help = false
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
params.reference_segments = 0  // Genome segment size for parallel variant calling (bp)
params.call_invar_sites = false  // Call invariant sites with GATK HaplotypeCaller
params.use_duplicate_reads = false  // Include reads flagged as duplicates by dupRemoval in GATK HaplotypeCaller calling
params.genomicsdb_batch_size = 200  // GenomicsDBImport batch size (samples per batch). Default 200 targets a single pass for typical panels; raise if import still batches across retries with increased memory.
params.bam_input = ""  // Optional: path to pre-existing BAM files
params.SRR_sample_map = ""  // Optional: CSV file mapping run IDs to sample names (Run_ID,Sample_Name)
params.slurm_queue = ""  // Required when using -profile slurm: SLURM partition name
params.plink_pca = false  // PCA on the pop. gen. VCF (plink2)
params.plink_relationships = false  // GRM and KING relationship matrices on the pop. gen. VCF (plink2)
params.plink_ld_prune = false  // LD pruning of the pop. gen. VCF (plink2)

include { gp_wf } from './workflows/gp_wf'
include { validateParams; formatProblems; helpMessage } from './modules/validate_params'

// ---------------------
// Work directory cleanup
// ---------------------
def cleanUpWorkDirIfClean() {
    def stats = workflow.stats
    def clean = workflow.success && stats.ignoredCount == 0 && stats.failedCount == 0

    if (clean) {
        def wd = workflow.workDir.toFile()
        if (wd.exists()) {
            log.info "Run completed cleanly (0 failed, 0 ignored tasks) -- deleting work directory: ${wd}"
            wd.deleteDir()
        }
    }
    else {
        log.warn """
        Work directory left in place (not cleaned up): ${workflow.workDir}
            success       : ${workflow.success}
            failed tasks  : ${stats.failedCount}
            ignored tasks : ${stats.ignoredCount}
        A failed or ignored task means at least one sample or segment did not
        produce what it should have -- inspect its work directory (named in
        .nextflow.log) for .command.err before deleting anything, and
        consider -resume once the cause is fixed.
        """.stripIndent()
    }
}


workflow {

   if (params.help) {
       log.info helpMessage()
       return
   }

   // ---------------------
   // Validate every parameter before anything is submitted.
   // See modules/validate_params.nf; all problems are reported in one block.
   // ---------------------
   // `args` holds any positional arguments Nextflow would otherwise discard --
   // the tell-tale of an unquoted glob that the shell expanded.
   def check = validateParams(args)

   if (check.problems) {
       error formatProblems(check.problems)
   }

   check.warnings.each { w -> log.warn w }

   workflow.onComplete { cleanUpWorkDirIfClean() }

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
       NCBI API key   : ${params.NCBI_API_key ? '(set)' : '(not set)'}
       Ploidy         : ${params.ploidy}
       Inv. site calls: ${params.call_invar_sites}
       Use dup. reads : ${params.use_duplicate_reads}
  
       Reference      : ${params.reference}
       Ref segments   : ${params.reference_segments}
       Min contig len : ${params.min_contig_length}
       BWA index      : ${params.bwa_index}
  
   Input data
       Local fastq    : ${params.reads}
       SRA ID file    : ${params.SRA_index}
       SRR-sample map : ${params.SRR_sample_map}
       Local bam      : ${params.bam_input}
  
   Resolved inputs
${check.summary.collect { k, v -> "       ${k.padRight(15)}: ${v}" }.join('\n')}
  
   Output options
       Working dir    : ${workflow.workDir}
       Output dir     : ${params.outdir}
       Keep BAM       : ${params.keep_bam}
       Keep GVCF      : ${params.keep_gvcf}

   Pop. gen. analyses
       PLINK PCA      : ${params.plink_pca}
       PLINK relation.: ${params.plink_relationships}
       PLINK LD prune : ${params.plink_ld_prune}

   SLURM
       Queue          : ${params.slurm_queue ?: '(not set — not using SLURM)'}
    """

   gp_wf()
}
