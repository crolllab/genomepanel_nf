include {trimSequences} from '../modules/fastp_trimming'
include {bwaIndex} from '../modules/bwa_index'
include {gatkIndex} from '../modules/gatk_index'
include {fastaIndex} from '../modules/index_fasta'
include {bwaMap} from '../modules/bwa_mapping'
include {samtoolsSort} from '../modules/samtools_sort'
include {addRG} from '../modules/picard_add_read_groups'
include {GATKHC} from '../modules/gatk4_hc'
include {dupRemoval} from '../modules/picard_duplicates_removal'
include {samtoolsRealignedIndex} from '../modules/samtools_index'
include {CombineGVCFs} from '../modules/combine_gvcfs'
include {GenotypeGVCFs} from '../modules/genotype_gvcfs'
include {FilterVCFs} from '../modules/filter_vcf'
include {CleanVCFs} from '../modules/clean_vcf'
include {ConcatVCFs} from '../modules/concat_vcf'
include {ConcatCleanVCFs} from '../modules/concat_clean_vcf'
include {RQualPlotting} from '../modules/r_plotting'
include {PLINKIBSPCA} from '../modules/plink_ibs_pca'

nextflow.enable.dsl=2

workflow variant_calling {

    if (!params.reference) {
        error "ERROR: Reference genome is not specified. Please provide an absolute path to the reference genome. The file must end with .fasta.\n"
        }

    if (!params.reads && !params.SRA_index) {
        error "ERROR: No input reads provided. Please provide local FASTQ files and/or a file with SRA run accessions.\n"
        }

    // Read SRA run accessions from a file

    if (params.SRA_index) {

        // First get and process IDs
        sra_list = file(params.SRA_index).readLines()
        read_pairs_ch = Channel.fromSRA(sra_list, apiKey: params.NCBI_api_key, cache: false, protocol: 'ftp')
        read_pairs_ch.view()
        }

    if (params.reads) {
            Channel
               .fromFilePairs(params.reads, checkIfExists: false)
               .set { read_pairs_local_ch }

            
            if (params.SRA_index) {
                read_pairs_ch = read_pairs_ch.mix(read_pairs_local_ch)
            } else {
                read_pairs_ch = read_pairs_local_ch
            }
    }

    // Trim reads  
    trimmed_ch = trimSequences(read_pairs_ch)

    // Preparing reference genome indexes and depth of coverage files
    bwa_index = bwaIndex(params.reference)
    gatk_index = gatkIndex(params.reference)
    fai_index = fastaIndex(params.reference)

    // BWA mem mapping
    mapped_sam = bwaMap(params.reference, bwa_index, trimmed_ch)

    // Sorting bam, adding read groups and removing duplicates
    sorted_bam = samtoolsSort(mapped_sam)
    rg_bam = addRG(sorted_bam)
    dedup_bams = dupRemoval(rg_bam)

    // GATK4 HaplotypeCaller
    dedup_bai = samtoolsRealignedIndex(dedup_bams)
    gvcf = GATKHC(params.reference, fai_index, gatk_index, dedup_bams, dedup_bai)

    // Extract all bam and bai paths and collect all of them
    gvcf_ch = gvcf.collect()

   // Extract chromosomes to parallelize SNP calling
    chromosomes_ch = fai_index
                            .splitCsv(sep: '\t')
                            .map { it[0] }


    // Run CombineGVCFs, collecting all GVCFs into a single file
    cgvcf = CombineGVCFs(gvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)
    cgvcf_ch = cgvcf.collect()

    // Run GenotypeGVCF
    vcf = GenotypeGVCFs(cgvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)
    vcf_ch = vcf.collect()
    // Run FilterVCFs
    fvcf = FilterVCFs(vcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)
    fvcf_ch = fvcf.collect()

    // Clean + concat VCFs
    clean_vcf = CleanVCFs(fvcf_ch, chromosomes_ch, params.reference, fai_index, gatk_index)
    clean_vcf_ch = clean_vcf.collect()
    concat_clean_vcf = ConcatCleanVCFs(clean_vcf_ch)

    // R plotting
    concat_vcf = ConcatVCFs(fvcf_ch)
    R_script = file('./VariantQualPlot.R')
    RQualPlotting(R_script, concat_vcf)

    // PLINK IBS analysis
    PLINKIBS(concat_clean_vcf)
}
