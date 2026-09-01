nextflow.enable.dsl=2

// ---------------------
// Module includes
// ---------------------
include { SRAresolve } from '../modules/resolve_SRA'
include { SRAdownloadPE } from '../modules/download_SRA'
include { SRAdownloadSE } from '../modules/download_SRA'
include { trimSequencesPE } from '../modules/fastp_trimming'
include { trimSequencesSE } from '../modules/fastp_trimming'
include { filterReference } from '../modules/filter_reference'
include { bwaIndex } from '../modules/bwa_index'
include { gatkIndex } from '../modules/gatk_index'
include { fastaIndex } from '../modules/index_fasta'
include { bwaMap } from '../modules/bwa_mapping'
include { samtoolsSort } from '../modules/samtools_sort'
include { addRG } from '../modules/picard_add_read_groups'
include { dupRemoval } from '../modules/picard_duplicates_removal'
include { loadBAMs } from '../modules/load_bams'
include { GATKHC } from '../modules/gatk4_hc'
include { cleanupBAMs } from '../modules/cleanup_bams'
include { GenomicsDBImport } from '../modules/genomicsdb_import'
include { GenotypeGVCFs } from '../modules/genotype_gvcfs'
include { FilterVCFs } from '../modules/filter_vcf'
include { CleanVCFs } from '../modules/clean_vcf'
include { ConcatVCFs } from '../modules/concat_vcf'
include { ConcatCleanVCFs } from '../modules/concat_clean_vcf'
include { RQualPlotting } from '../modules/r_plotting'
include { PopGenVCF } from '../modules/popgen_vcf'
include { PlinkPCA } from '../modules/plink_pca'
include { PlinkRelationships } from '../modules/plink_relationships'
include { PlinkLDPrune } from '../modules/plink_ld_prune'
include { RSummarizingBWA } from '../modules/r_process_summary_bwa'
include { RSummarizingFASTP } from '../modules/r_process_summary_fastp'
include { ReportIgnoredSamples } from '../modules/report_ignored'
include { MergeGVCFs } from '../modules/merge_gvcfs'
include { PipelineStatistics } from '../modules/pipeline_statistics'

// ---------------------
// Main workflow
// ---------------------
workflow gp_wf {

    // ---------------------
    // Input checks
    // ---------------------
    // Parameter and input-file validation happens up front in main.nf, via
    // validateParams() in modules/validate_params.nf, so that every problem is
    // reported in one block before any task is submitted. The `checkIfExists`
    // flags below are a second line of defence: without them a missing file is
    // staged as a broken symlink and surfaces as a container error six retries
    // later, rather than as a Nextflow message naming the file.

    // ---------------------
    // Reference filtering (optional)
    // ---------------------
    if (params.min_contig_length && params.min_contig_length != false) {
        // Filter reference by contig length
        filterReference(Channel.fromPath(params.reference, checkIfExists: true), params.min_contig_length)
        reference_to_use = filterReference.out.filtered_fasta.collect()
    } else {
        // Use original reference
        reference_to_use = Channel.fromPath(params.reference, checkIfExists: true).collect()
    }

    // ---------------------
    // Reference indexes (needed for both read and BAM input)
    // ---------------------
    gatk_index  = gatkIndex(reference_to_use)
    fai_index   = fastaIndex(reference_to_use)

    // ---------------------
    // Input processing: BAM files OR reads (SRA/local)
    // ---------------------
    if (!params.bam_input) {
    // Process reads through full pipeline
    
    // ---------------------
    // SRA metadata + downloads
    // ---------------------
    if (params.SRA_index) {

    // Input SRA index file
    // Step 0: Make a channel from the SRA index file
    sra_file_ch = Channel.fromPath(params.SRA_index, checkIfExists: true)
    
    // First run SRAresolve to get SRR IDs and URLs
    SRAresolve(sra_file_ch)

    // Parse the URL file to create download channels with ENA URLs
    url_data = SRAresolve.out.url_file
        .splitCsv(sep: '\t', header: true)
    
    // Split into PE and SE channels with URL information
    pe_with_urls = url_data
        .filter { it.Layout == 'PE' }
        .map { tuple(it.SRR_ID, it.URL_1 ?: "", it.URL_2 ?: "", it.Source ?: "NCBI") }
    
    se_with_urls = url_data
        .filter { it.Layout == 'SE' }
        .map { tuple(it.SRR_ID, it.URL_1 ?: "", it.Source ?: "NCBI") }

    // Every accession SRAresolve managed to resolve. Kept so that accessions
    // lost to the download step's 'ignore' strategy can be named at the end.
    sra_expected_ids = pe_with_urls.map { it[0] }.mix(se_with_urls.map { it[0] })

    // Now run downloads with URL information for hybrid approach
    SRAdownloadPE(pe_with_urls)
    SRAdownloadSE(se_with_urls)

    } else {
        sra_expected_ids = Channel.empty()
    }

    // ---------------------
    // Local FASTQ reads
    // ---------------------
    if (params.reads) {
        // Support semicolon-separated list of glob patterns (e.g. 'path1/**/{1,2}.fastq.gz;path2/**/{1,2}.fastq.gz')
        def reads_patterns = params.reads.tokenize(';').collect { it.trim() }
        // Create channel from read pairs - let Nextflow handle the pairing
        read_pairs_local_ch = Channel.fromFilePairs(
            reads_patterns,
            flat: false, // keeps paired R1/R2 in a tuple
            size: 2,  // expect exactly 2 files per pair
            checkIfExists: true
        )
        
        // Reformat to extract proper sample IDs
        // Find common prefix between paired files to use as sample ID
        local_pe_formatted = read_pairs_local_ch.map { sample_id, reads_list ->
            // Get basenames without extensions
            def name1 = reads_list[0].name.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')
            def name2 = reads_list[1].name.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')
            
            // Find longest common prefix (this is the true sample ID)
            def minLen = Math.min(name1.length(), name2.length())
            def commonPrefix = (0..<minLen).takeWhile { name1[it] == name2[it] }.collect { name1[it] }.join('')
            
            // Remove trailing separators (_, ., -)
            commonPrefix = commonPrefix.replaceAll(/[._-]+$/, '')
            
            return [commonPrefix, reads_list[0], reads_list[1], 'local']
        }
    } else {
        local_pe_formatted = Channel.empty()
    }


    // Only create SRA channel if SRA processing was enabled
    if (params.SRA_index) {
        // Simple channel formatting - downloads that succeed will have outputs
        // Downloads that still fail after retries will not emit anything
        // Add source tag to distinguish from local files
        sra_pe_formatted = SRAdownloadPE.out.map { sample_id, r1, r2 -> [sample_id, r1, r2, 'SRA'] }
        sra_se_formatted = SRAdownloadSE.out.map { sample_id, r1 -> [sample_id, r1, 'SRA'] }
    } else {
        sra_pe_formatted = Channel.empty()
        sra_se_formatted = Channel.empty()
    }

    combined_pe_ch = sra_pe_formatted.mix(local_pe_formatted)

    // ---------------------
    // Read trimming, reporting
    // ---------------------
    // Connect channels to trimming processes
    trimSequencesPE(combined_pe_ch)
    trimSequencesSE(sra_se_formatted)


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
    // Track silently dropped samples
    // ---------------------
    // Downloading and trimming both switch to 'ignore' once their retries run
    // out, so a failed sample vanishes from the channel instead of stopping the
    // run. Compare the IDs entering each stage with those leaving it, and write
    // the difference to 1_sra_downloads/ignored_samples.txt. Sample renaming
    // via --SRR_sample_map happens later (at addRG), so IDs are directly
    // comparable here.
    entered_trimming_ids = combined_pe_ch.map { it[0] }.mix(sra_se_formatted.map { it[0] })
    downloaded_ids       = sra_pe_formatted.map { it[0] }.mix(sra_se_formatted.map { it[0] })

    ReportIgnoredSamples(
        sra_expected_ids.collect().ifEmpty([]),
        downloaded_ids.collect().ifEmpty([]),
        entered_trimming_ids.collect().ifEmpty([]),
        trimmed_ch.map { it[0] }.collect().ifEmpty([])
    )
    ignored_report_ch = ReportIgnoredSamples.out.report


    // ---------------------
    // BWA index (only needed for read input)
    // ---------------------
    // Conditionally build or use provided BWA index
    if (params.bwa_index) {
        // Use provided BWA index files
        // Collect into value channels that can be reused for each sample
        bwa_amb = Channel.fromPath("${params.bwa_index}.amb", checkIfExists: true).collect()
        bwa_ann = Channel.fromPath("${params.bwa_index}.ann", checkIfExists: true).collect()
        bwa_bwt = Channel.fromPath("${params.bwa_index}.bwt.2bit.64", checkIfExists: true).collect()
        bwa_pac = Channel.fromPath("${params.bwa_index}.pac", checkIfExists: true).collect()
        bwa_0123 = Channel.fromPath("${params.bwa_index}.0123", checkIfExists: true).collect()
    } else {
        // Build BWA index from reference - returns 5 separate outputs
        (bwa_amb, bwa_ann, bwa_bwt, bwa_pac, bwa_0123) = bwaIndex(reference_to_use)
    }
    
    // ---------------------
    // Mapping
    // ---------------------
    bwaMap(reference_to_use, bwa_amb, bwa_ann, bwa_bwt, bwa_pac, bwa_0123, trimmed_ch)


    // ---------------------
    // Post-processing BAM
    // ---------------------

    samtoolsSort(bwaMap.out)
    bam_sorted = samtoolsSort.out.bam

    bam_reports = samtoolsSort.out.report
    bam_reports_ch = bam_reports.collect()

    // ---------------------
    // SRR to Sample mapping (optional)
    // ---------------------
    // If a sample map file is provided, use it; otherwise use an empty placeholder file
    // The placeholder file must exist so Channel.fromPath can stage it properly
    if (params.SRR_sample_map && params.SRR_sample_map instanceof String) {
        sample_map_file = Channel.fromPath(params.SRR_sample_map, checkIfExists: true).collect()
    } else {
        sample_map_file = Channel.fromPath("${projectDir}/NO_SAMPLE_MAP.txt", checkIfExists: false).collect()
    }

    // Updated workflow
    addRG(bam_sorted, sample_map_file)
    dedup_bams = dupRemoval(addRG.out.bam)
    dedup_with_index = dedup_bams.bam
    bams_to_cleanup = dedup_with_index   // pipeline-generated BAMs; deleted after all GATKHC tasks complete
    
    } else {
    // ---------------------
    // Load pre-existing BAM files
    // ---------------------
    // Parse BAM files from glob pattern
    // Extract sample name by removing _RG_dedup suffix if present
    // Like --reads, several locations may be given, separated by semicolons.
    // Indexes are checked up front in validateParams(); this repeats the lookup
    // only to pick whichever of the two naming conventions is actually present.
    def bam_patterns = params.bam_input.tokenize(';').collect { it.trim() }.findAll { it }
    bam_ch = Channel
        .fromPath(bam_patterns, checkIfExists: true)
        .map { bam_file ->
            def sample_name = bam_file.baseName.replaceAll(/_RG_dedup$/, '')
            def bai_file = [ file("${bam_file}.bai"),
                             file("${bam_file.parent}/${bam_file.baseName}.bai") ].find { it.exists() }
            if (!bai_file) {
                error "No BAM index found for ${bam_file}.\nExpected ${bam_file}.bai or ${bam_file.parent}/${bam_file.baseName}.bai — create one with: samtools index ${bam_file}"
            }
            tuple(sample_name, bam_file, bai_file)
        }
    
    dedup_with_index = loadBAMs(bam_ch).bam
    bams_to_cleanup = Channel.empty()   // user-provided BAMs are never deleted by the pipeline
    
    // When using BAM input, BWA indices aren't needed but GATKHC module expects them
    // Use the same BWA index logic as for read processing
    if (params.bwa_index) {
        bwa_amb = Channel.fromPath("${params.bwa_index}.amb", checkIfExists: true).collect()
        bwa_ann = Channel.fromPath("${params.bwa_index}.ann", checkIfExists: true).collect()
        bwa_bwt = Channel.fromPath("${params.bwa_index}.bwt.2bit.64", checkIfExists: true).collect()
        bwa_pac = Channel.fromPath("${params.bwa_index}.pac", checkIfExists: true).collect()
        bwa_0123 = Channel.fromPath("${params.bwa_index}.0123", checkIfExists: true).collect()
    } else {
        // Build BWA index from reference even for BAM input (needed by GATKHC module)
        (bwa_amb, bwa_ann, bwa_bwt, bwa_pac, bwa_0123) = bwaIndex(reference_to_use)
    }
    
    }  // End of BAM input vs reads processing conditional

    // ---------------------
    // Parallel SNP calling by genome segments
    // ---------------------
    // Parse FAI file to create intervals based on params.reference_segments
    // FAI format: chr_name, length, offset, linebases, linewidth
    // If reference_segments is 0, use full chromosomes (no segmentation)
    segment_size = params.reference_segments as Integer
    
    intervals_ch = fai_index
        .splitCsv(sep: '\t')
        .flatMap { row ->
            def chr = row[0]
            def chr_length = row[1] as Integer
            def intervals = []
            
            if (segment_size == 0) {
                // No segmentation - use full chromosome
                def interval_name = chr  // Just chromosome name for GATK -L
                def interval_key = chr   // Key for grouping
                intervals.add([chr, interval_name, interval_key])
            } else {
                // Generate segments for this chromosome
                (1..chr_length).step(segment_size).each { start ->
                    def end = Math.min(start + segment_size - 1, chr_length)
                    def interval_name = "${chr}:${start}-${end}"
                    def interval_key = "${chr}_${start}_${end}"  // For grouping later
                    intervals.add([chr, interval_name, interval_key])
                }
            }
            return intervals
        }

    // ---------------------
    // GATK HaplotypeCaller (split by 1 Mb segments)
    // ---------------------
    // Combine each sample with each interval: [sample_id, bam, bai] × [chr, interval, key] → [sample_id, bam, bai, chr, interval, key]
    dedup_interval_ch = dedup_with_index.combine(intervals_ch)
    
    // dedup_interval_ch structure: [sample_id, bam, bai, chr, interval_name, interval_key]
    // GATKHC needs: [sample_id, bam, bai, interval_name, chr]
    dedup_for_gatk = dedup_interval_ch.map { sample_id, bam, bai, chr, interval_name, interval_key ->
        [sample_id, bam, bai, interval_name, chr]
    }
    
    // Split GATKHC output: one sub-channel for downstream VCF processing, one to count
    // completions. .count() only resolves after ALL GATKHC tasks emit, making it a safe
    // barrier that proves every BAM has finished being used before we delete it.
    gvcf_mmap = GATKHC(reference_to_use, fai_index, gatk_index, bwa_amb, bwa_ann, bwa_bwt, bwa_pac, bwa_0123, dedup_for_gatk)
        .multiMap { sample_id, chr, files ->
            main:     [sample_id, chr, files]
            sentinel: chr
        }
    gvcf        = gvcf_mmap.main
    gatkhc_done = gvcf_mmap.sentinel.count()

    // Delete dedup BAM files once ALL GATKHC tasks have completed.
    // bams_to_cleanup is empty for --bam_input runs (user files are never deleted).
    cleanupBAMs(bams_to_cleanup, gatkhc_done)

    // ---------------------
    // Merge per-segment GVCFs into single per-sample GVCF
    // Only when keep_gvcf is enabled AND reference_segments > 0 (sub-chromosomal segmentation)
    // ---------------------
    if (params.keep_gvcf && segment_size > 0) {
        gvcf_by_sample = gvcf
            .map { sample_id, chr, files -> [sample_id, files] }
            .groupTuple(by: 0)
            .map { sample_id, file_lists -> [sample_id, file_lists.flatten()] }
        MergeGVCFs(gvcf_by_sample)
    }

    // ---------------------
    // Combine, genotype, filter VCFs (per 1 Mb segment)
    // ---------------------

    // Group GVCFs by segment (collect all samples for each 1 Mb segment)
    // GATKHC outputs: tuple val(chr), path("${sample_id}_${interval_safe}.g.vcf.gz*")
    // We need to group by [chr, interval] to keep segments separate
    // First, add back interval information for grouping
    gvcf_with_interval = gvcf.combine(intervals_ch)
        .filter { sample_id, gvcf_chr, gvcf_files, int_chr, int_name, int_key ->
            // Match GVCF files with their corresponding interval
            // Check if any file contains the interval key
            gvcf_chr == int_chr && gvcf_files.any { it.name.contains(int_key.replaceAll('[:\\-]', '_')) }
        }
        .map { sample_id, gvcf_chr, gvcf_files, int_chr, int_name, int_key ->
            // Return [interval_name, chr, files] for processing
            [int_name, int_chr, gvcf_files]
        }
    
    // Group all samples for the same segment together
    gvcf_grouped = gvcf_with_interval
        .groupTuple(by: 0)  // Group by interval_name (first element)
        .map { interval, chr_list, file_lists ->
            // Take first chr (they're all the same), flatten files
            [chr_list[0], interval, file_lists.flatten()]
        }
    
    // Import all GVCFs per interval into a GenomicsDB workspace (batch-aware, scales to 1000s of samples)
    // Output: tuple val(chr), val(interval), path(genomicsdb_dir)
    genomicsdb = GenomicsDBImport(gvcf_grouped, reference_to_use, fai_index, gatk_index)

    // Run GenotypeGVCFs against the GenomicsDB workspace
    vcf = GenotypeGVCFs(genomicsdb, reference_to_use, fai_index, gatk_index)

    // ---------------------
    // Run FilterVCFs based on hard filters - process each 1 Mb segment independently
    // ---------------------
    fvcf = FilterVCFs(vcf, reference_to_use, fai_index, gatk_index)

   // ---------------------
   // Clean VCFs - process each 1 Mb segment independently
   // ---------------------
    clean_vcf = CleanVCFs(fvcf, reference_to_use, fai_index, gatk_index)
    
    // ---------------------
    // Concatenate all segments to create final VCFs
    // ---------------------
    // Extract just the file paths from the tuples (drop chr and interval) before collecting
    clean_vcf_ch = clean_vcf.map{ chr, interval, files -> files }.collect()
    concat_clean_vcf = ConcatCleanVCFs(clean_vcf_ch)

    // Use clean VCF to produce a MAF, thinned VCF for e.g. PCA/clustering analyses
    popgen_vcf = PopGenVCF(concat_clean_vcf)

    // ---------------------
    // Optional PLINK analyses on the pop. gen. VCF
    // ---------------------
    plink_done = Channel.empty()
    if (params.plink_pca) {
        PlinkPCA(popgen_vcf)
        plink_done = plink_done.mix(PlinkPCA.out[0])
    }
    if (params.plink_relationships) {
        PlinkRelationships(popgen_vcf)
        plink_done = plink_done.mix(PlinkRelationships.out[0])
    }
    if (params.plink_ld_prune) {
        PlinkLDPrune(popgen_vcf)
        plink_done = plink_done.mix(PlinkLDPrune.out[0])
    }

    // ---------------------
    // Concat all variants (incl. low qual)
    // ---------------------
    // Extract just the file paths from the tuples before collecting
    fvcf_ch = fvcf.map{ chr, interval, files -> files }.collect()
    concat_vcf = ConcatVCFs(fvcf_ch)

    // ---------------------
    // R QC report + optional FASTP/BWA summaries
    // ---------------------
    fastp_summary_script = Channel.value(file("${projectDir}/modules/r_process_summary_fastp.R"))
    bwa_summary_script   = Channel.value(file("${projectDir}/modules/r_process_summary_bwa.R"))
    qual_plot_script     = Channel.value(file("${projectDir}/modules/r_plotting.R"))

    if (!params.bam_input) {
        RSummarizingFASTP(fastp_json_ch, fastp_summary_script)
        RSummarizingBWA(bam_reports_ch, bwa_summary_script)
        // Pass TSV summary files to the plotting process
        RQualPlotting(concat_vcf, RSummarizingFASTP.out, RSummarizingBWA.out,
            ignored_report_ch, qual_plot_script,
            Channel.value(workflow.manifest.version),
            Channel.value(workflow.start.format('yyyy-MM-dd HH:mm')))

        // Mix all final outputs including R summaries and the HTML report
        all_done = concat_clean_vcf.mix(concat_vcf)
            .mix(RSummarizingFASTP.out)
            .mix(RSummarizingBWA.out)
            .mix(RQualPlotting.out.report)
            .mix(plink_done)
            .collect()
    } else {
        // For BAM input, no FASTP/BWA TSV files available. Nothing can be
        // dropped by download or trimming either, so no ignored-sample report.
        RQualPlotting(concat_vcf, Channel.value([]), Channel.value([]),
            Channel.value([]), qual_plot_script,
            Channel.value(workflow.manifest.version),
            Channel.value(workflow.start.format('yyyy-MM-dd HH:mm')))

        all_done = concat_clean_vcf.mix(concat_vcf)
            .mix(RQualPlotting.out.report)
            .mix(plink_done)
            .collect()
    }

    // ---------------------
    // Generate pipeline execution statistics
    // ---------------------
    PipelineStatistics(all_done, workflow.launchDir.resolve(params.outdir).resolve("10_reports").resolve("pipeline_trace.txt"))

}
