nextflow.enable.dsl=2

// ---------------------
// Module includes
// ---------------------
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
    // SRA reads
    // ---------------------
    if (params.SRA_index) {

        // First get and process IDs
        sra_list = file(params.SRA_index).readLines()
        read_pairs_sra_ch = Channel.fromSRA(sra_list, 
            apiKey: params.NCBI_API_key, 
            cache: true, 
            retryPolicy: [jitter: 0.25, maxAttempts: 10, delay: '30s', maxDelay: '10m'],
            protocol: 'ftp')

   //     read_pairs_sra_ch.view()
       }

    // ---------------------
    // Local FASTQ reads
    // ---------------------
    if (params.reads) {
        read_pairs_local_ch = Channel.fromFilePairs(
            params.reads,
            checkIfExists: true,   // make sure files exist
            flat: false             // keeps paired R1/R2 in a tuple
        )
    }
    // ---------------------
    // Merge reads channels
    // ---------------------
    // Filter out empty entries first
    // def filtered_sra_ch = read_pairs_sra_ch.filter { it != null && it.size() > 0 }
    // def filtered_local_ch = read_pairs_local_ch.filter { it != null && it.size() > 0 }

  
    if (params.reads && params.SRA_index) {
        read_pairs_ch = read_pairs_sra_ch.mix(read_pairs_local_ch)
    } else if (params.reads) {
        read_pairs_ch = read_pairs_local_ch
    } else {
        read_pairs_ch = read_pairs_sra_ch
    }   

    // ---------------------
    // Trim reads (separate for SE and PE)
    // ---------------------

read_se_ch = read_pairs_ch.filter { sample_id, reads ->
    reads instanceof String        // SE: reads is a single path
}

read_pe_ch = read_pairs_ch.filter { sample_id, reads ->
    reads instanceof List          // PE: reads is a list of 2 paths
}
//    read_se_ch = read_pairs_ch.filter { it.size() == 2 }
//    read_pe_ch = read_pairs_ch.filter { it.size() == 3 }

//    trimmed_se_ch = trimSequencesSE(read_se_ch)[0]
    
//    trimmed_pe_ch = trimSequencesPE(read_pe_ch)[0]
//    fastp_json_ch = trimSequencesPE(read_pe_ch)[1]
    
    // Merge if you want a unified channel of trimmed outputs
//
//     trimmed_ch = trimmed_se_ch.mix(trimmed_pe_ch)

    // Trim SE + PE reads
    trimmed_se_ch = trimSequencesSE(read_se_ch)
    trimmed_pe_ch = trimSequencesPE(read_pe_ch)

    // Collect the JSON reports (second output channel, `emit: report`)
    se_reports_ch = trimmed_se_ch[1].collect()
    pe_reports_ch = trimmed_pe_ch[1].collect()

    // Merge SE + PE reports into one channel
    fastp_json_ch = se_reports_ch.mix(pe_reports_ch)

    // Merge SE + PE trimmed reads into one channel
    trimmed_ch = trimmed_se_ch[0].mix(trimmed_pe_ch[0])

    // ---------------------
    // Reference indexes
    // ---------------------
    bwa_index   = bwaIndex(params.reference)
    gatk_index  = gatkIndex(params.reference)
    fai_index   = fastaIndex(params.reference)

    // ---------------------
    // Mapping
    // ---------------------
    mapped_sam = bwaMap(params.reference, bwa_index, trimmed_ch)

    // ---------------------
    // Post-processing BAM
    // ---------------------
    sorted_bam = samtoolsSort(mapped_sam)
    bam_reports_ch = sorted_bam[1].collect()

    rg_bam     = addRG(sorted_bam[0])

    dedup_bams = dupRemoval(rg_bam)

    // ---------------------
    // Transform BAM tuples to include sample ID
    // ---------------------
    dedup_with_index = dedup_bams
        .map { bam, bai ->
            def sample_id = bam.baseName.replaceFirst(/_RG_dedup$/, '')
            tuple(sample_id, bam, bai)
        }

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
    gvcf_ch = gvcf.collect()
    cgvcf = CombineGVCFs(gvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)

    // Run GenotypeGVCF
    cgvcf_ch = cgvcf.collect()
    vcf = GenotypeGVCFs(cgvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)

    // ---------------------
    // Run FilterVCFs
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
    PopGenVCF(concat_clean_vcf)

    // ---------------------
    // Concat all variants (incl. low qual) + R plotting
    // ---------------------
    concat_vcf = ConcatVCFs(fvcf_ch)
    R_script = file('./R_plotting.R')
    RQualPlotting(R_script, concat_vcf)

    // ---------------------
    // Summarize FASTP and BWA steps with R
    // ---------------------
    RSummarizingFASTP(fastp_json_ch)
    RSummarizingBWA(bam_reports_ch)    
}
