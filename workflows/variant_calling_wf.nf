nextflow.enable.dsl=2

// ---------------------
// Module includes
// ---------------------
include { SRAresolve } from '../modules/resolve_SRA'
include { SRAdownloadPE } from '../modules/download_SRA'
include { SRAdownloadSE } from '../modules/download_SRA'
include { CollectFailedDownloads } from '../modules/download_SRA'
include { trimSequencesPE } from '../modules/fastp_trimming'
include { trimSequencesSE } from '../modules/fastp_trimming'
include { bwaIndex } from '../modules/bwa_index'
include { gatkIndex } from '../modules/gatk_index'
include { fastaIndex } from '../modules/index_fasta'
include { bwaMap } from '../modules/bwa_mapping'
include { samtoolsSort } from '../modules/samtools_sort'
include { addRG } from '../modules/picard_add_read_groups'
include { dupRemoval } from '../modules/picard_duplicates_removal'
include { samtoolsRealignedIndex } from '../modules/samtools_index'
include { GATKHC } from '../modules/gatk4_hc'
include { CombineGVCFs } from '../modules/combine_gvcfs'
include { GenotypeGVCFs } from '../modules/genotype_gvcfs'
include { FilterVCFs } from '../modules/filter_vcf'
include { CleanVCFs } from '../modules/clean_vcf'
include { ConcatVCFs } from '../modules/concat_vcf'
include { ConcatCleanVCFs } from '../modules/concat_clean_vcf'
include { RQualPlotting } from '../modules/r_plotting'
include { PopGenVCF } from '../modules/popgen_vcf'
include { RSummarizingBWA } from '../modules/r_process_summary_bwa'
include { RSummarizingFASTP } from '../modules/r_process_summary_fastp'

// ---------------------
// Main workflow
// ---------------------
workflow variant_calling {

    // ---------------------
    // Input checks
    // ---------------------
    if (!params.reference) {
       exit 1, "ERROR: Reference genome is not specified (.fasta file required)."
    }
    
    if (!params.reads && !params.SRA_index) {
       exit 1, "ERROR: No input reads provided. Supply local FASTQ files and/or SRA run accessions."
    }
    
    // ---------------------
    // SRA metadata + downloads
    // ---------------------
    if (params.SRA_index) {

    // Input SRA index file
    // Step 0: Make a channel from the SRA index file
    sra_file_ch = Channel.fromPath(params.SRA_index)
    
    // First run SRAresolve
    SRAresolve(sra_file_ch)

    // Then use its outputs to create channels for download processes
    pe_ids = SRAresolve.out.pe_file
        .splitText()
        .map { it.trim() }

    se_ids = SRAresolve.out.se_file
        .splitText()
        .map { it.trim() }

    // Now run downloads - these will wait for SRAresolve to complete
    SRAdownloadPE(pe_ids)
    SRAdownloadSE(se_ids)

    // Collect failure reports
    pe_failures = SRAdownloadPE.out[1].collect()
    se_failures = SRAdownloadSE.out[1].collect()
    all_failures = pe_failures.mix(se_failures).collect()

    CollectFailedDownloads(all_failures)

    }

    // ---------------------
    // Local FASTQ reads
    // ---------------------
    if (params.reads) {
        read_pairs_local_ch = Channel.fromFilePairs(
            params.reads,
            checkIfExists: true,
            flat: false // keeps paired R1/R2 in a tuple
        )
        local_pe_formatted = read_pairs_local_ch.map { sample_id, reads_list ->
            [sample_id, reads_list[0], reads_list[1]]
        }
    } else {
        local_pe_formatted = Channel.empty()
    }


    // Only create SRA channel if SRA processing was enabled
    if (params.SRA_index) {
        sra_pe_formatted = SRAdownloadPE.out[0].map { sample_id, reads ->
            [sample_id, reads[0], reads[1]]
        }
        sra_se_formatted = SRAdownloadSE.out[0]
    } else {
        sra_pe_formatted = Channel.empty()
        sra_se_formatted = Channel.empty()
    }

    combined_pe_ch = sra_pe_formatted.mix(local_pe_formatted)

    // ---------------------
    // Read trimming, reporting
    // ---------------------
    // Connect channels to trimming processes
    trimSequencesSE(sra_se_formatted)
    trimSequencesPE(combined_pe_ch)


    // Access trimmed outputs
    pe_trimmed = trimSequencesPE.out.reads
    se_trimmed = trimSequencesSE.out.reads
    pe_reports = trimSequencesPE.out.report
    se_reports = trimSequencesSE.out.report

    // Collect the JSON reports (second output channel, `emit: report`)
    pe_reports_ch = pe_reports.collect()
    se_reports_ch = se_reports.collect()

    // Merge SE + PE reports into one channel
    fastp_json_ch = se_reports_ch.concat(pe_reports_ch).collect()  // waits for both


    // Merge SE + PE trimmed reads into one channel
    trimmed_ch = pe_trimmed.mix(se_trimmed)


    // ---------------------
    // Reference indexes
    // ---------------------
    bwa_index   = bwaIndex(params.reference)
    gatk_index  = gatkIndex(params.reference)
    fai_index   = fastaIndex(params.reference)
    // ---------------------
    // Mapping
    // ---------------------
    bwaMap(params.reference, bwa_index, trimmed_ch)


    // ---------------------
    // Post-processing BAM
    // ---------------------

    samtoolsSort(bwaMap.out)
    bam_sorted = samtoolsSort.out.bam

    bam_reports = samtoolsSort.out.report
    bam_reports_ch = bam_reports.collect()

//    addRG(bam_sorted)
//    dedup_bams = dupRemoval(addRG.out)

    // Updated workflow
    addRG(bam_sorted)
    dedup_bams = dupRemoval(addRG.out.bam)
    dedup_with_index = dedup_bams.bam  // or just use dedup_bams directly

    // ---------------------
    // GATK HaplotypeCaller
    // ---------------------
    gvcf = GATKHC(params.reference, fai_index, gatk_index, bwa_index, dedup_with_index)

    // ---------------------
    // Parallel SNP calling by chromosome
    // ---------------------
    chromosomes_ch = fai_index
        .splitCsv(sep: '\t')
        .map { it[0] }

    // ---------------------
    // Combine, genotype, filter VCFs
    // ---------------------

    // Run CombineGVCFs
    gvcf_ch = gvcf.collect()
    cgvcf = CombineGVCFs(gvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)

    // Run GenotypeGVCF
    cgvcf_ch = cgvcf.collect()
    vcf = GenotypeGVCFs(cgvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)


    // ---------------------
    // Run FilterVCFs based on hard filters
    // ---------------------
    vcf_ch = vcf.collect()
    fvcf = FilterVCFs(vcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)

   // ---------------------
   // Clean + concat clean VCFs
   // ---------------------
    fvcf_ch = fvcf.collect()
    clean_vcf = CleanVCFs(fvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)
    clean_vcf_ch = clean_vcf.collect()
    concat_clean_vcf = ConcatCleanVCFs(clean_vcf_ch)

    // Use clean VCF to produce a MAF, thinned VCF for e.g. PCA/clustering analyses
    PopGenVCF(concat_clean_vcf)

    // ---------------------
    // Concat all variants (incl. low qual) + R plotting
    // ---------------------
    concat_vcf = ConcatVCFs(fvcf_ch)
    R_script = file('./R_plotting.R')
    RQualPlotting(concat_vcf)

    // ---------------------
    // Summarize FASTP and BWA steps with R
    // ---------------------
    RSummarizingFASTP(fastp_json_ch)
    RSummarizingBWA(bam_reports_ch)    

}
