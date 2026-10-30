# Pipeline output

All output files are written to the directory specified by `--outdir` (default: `./nf_output`).

Output folders are **numbered in pipeline order**. A folder is only created when the step that
fills it actually runs, so gaps in the numbering are normal — a `--bam_input` run has no
`1_sra_downloads/`, one without any `--plink_*` flag has no `9_plink/`, one without `--cnv` has
no `11_cnv/`.

```
<outdir>/
├── 1_sra_downloads/   Accession URLs + dropped-sample report     read input
├── 2_reference/       Length-filtered reference genome            --min_contig_length
├── 3_fastq_stats/     Per-sample fastp JSON + summary table       read input
├── 4_bwa_mapping/     Per-sample flagstat JSON + summary table    read input
├── 5_bam_files/       Per-sample duplicate-marked BAM files       --keep_bam
├── 6_gvcf_files/      Per-sample GVCF files                       --keep_gvcf
├── 7_variants/        Final VCFs and variant quality metrics      always
├── 8_popgen_vcf/      Thinned, MAF-filtered population VCF        always
├── 9_plink/           PCA, relatedness and LD pruning results     any --plink_*
├── 10_reports/        HTML QC report and run statistics           always
└── 11_cnv/            Copy-number variant calls                    --cnv
```

---

## `1_sra_downloads/`

The three accession files are only generated when `--SRA_index` is used.
`ignored_samples.txt` is written for any read-based run, including `--reads` only.

| File | Description |
|------|-------------|
| `NCBI_download_urls.tsv` | Resolved SRR accessions, layout (PE/SE), and download URLs |
| `NCBI_SRR_PE_accessions.txt` | List of all paired-end SRR run IDs |
| `NCBI_SRR_SE_accessions.txt` | List of all single-end SRR run IDs |
| `ignored_samples.txt` | Samples dropped before variant calling, split by the stage that dropped them. Always written, even when nothing was dropped. |
| `hifi/` | The same three accession files for `--hifi_SRA_index` (PacBio HiFi, experimental). |

!!! warning "Check `ignored_samples.txt` before treating a run as complete"
    Every per-sample step from download to duplicate marking is configured to
    give up on a sample rather than abort the whole run. When that happens the sample is **missing from the
    final VCF**, but the pipeline still finishes successfully — nothing in the
    Nextflow summary flags it.

    This file names every such sample, and the same list appears in the
    **Sample completeness** section at the top of
    `10_reports/pipeline_report.html`. If it reports `Total dropped: 0`, the panel
    is complete.

---

## `2_reference/`

Only generated when `--min_contig_length` is set.

| File | Description |
|------|-------------|
| `<reference>.red.fasta` | The reference genome with all contigs shorter than the threshold removed. This filtered FASTA is what the rest of the run maps and calls against. |
| `<reference>.filter_stats.txt` | Number and total length of contigs kept and discarded. |

---

## `3_fastq_stats/`

Read-trimming QC, one JSON per sample plus a combined table. Not generated for `--bam_input` runs.

| File | Description |
|------|-------------|
| `<sample>_PE_fastp.json` / `<sample>_SE_fastp.json` | Raw per-sample fastp report. |
| `fastp_summary.tsv` | Per-sample fastp statistics (reads before/after trimming, Q20/Q30 rates, GC content, etc.). Wide format — one column per sample. |

---

## `4_bwa_mapping/`

Alignment QC, one JSON per sample plus a combined table. Not generated for `--bam_input` runs.

| File | Description |
|------|-------------|
| `<sample>_flagstat.json` | Raw per-sample `samtools flagstat` output. |
| `<run>_HiFi_flagstat.json` | The same for a PacBio HiFi run mapped with pbmm2 (experimental); it appears in `bwa_summary.tsv` as the column `<run>_HiFi`. |
| `bwa_summary.tsv` | Per-sample BWA-mem2 alignment statistics (total reads, mapped reads, mapping rate, etc.). Wide format — one column per sample. |

---

## `5_bam_files/`

Saved when `--keep_bam true` is set. Contains per-sample, coordinate-sorted, duplicate-marked BAM files and their `.bai` index files.

```
<sample>_RG_dedup.bam
<sample>_RG_dedup.bam.bai
```

---

## `6_gvcf_files/`

Saved when `--keep_gvcf true` is set. Contains per-sample GVCF files emitted by GATK HaplotypeCaller before joint genotyping. When the reference is processed in segments (`--reference_segments` > 0), the per-segment GVCFs are concatenated into one file per sample.

---

## `7_variants/`

### `final_variants.vcf.gz` / `.tbi`

The main joint-genotyped VCF containing **all identified variant sites** across all samples. Variants failing the GATK VariantFiltration criteria are flagged in the `FILTER` column (not removed).

Filtration criteria applied:

| Filter tag | Criterion | Rationale |
|------------|-----------|-----------|
| `QD2` | `QD < 20.0` | Quality by depth — low values indicate low-confidence variants |
| `MQ30` | `MQ < 30.0` | Mapping quality — low values suggest incorrect mapping |
| `ReadPosRankSum` | `ReadPosRankSum < -2.0` or `> 2.0` | Strand bias in read position |
| `MQRankSum` | `MQRankSum < -2.0` or `> 2.0` | Mapping quality rank-sum bias |
| `BaseQRankSum` | `BaseQRankSum < -2.0` or `> 2.0` | Base quality rank-sum bias |

!!! note
    No `QUAL`-based filter is applied because QUAL scores are sample-size dependent.

### `final_variants.clean.vcf.gz` / `.tbi`

High-quality VCF containing only variants with **`FILTER = PASS`** — a subset of `final_variants.vcf.gz`.

### Variant quality metrics

| File | Description |
|------|-------------|
| `final_variants.metrics.csv.gz` | Compressed CSV of per-variant quality metrics (`CHROM`, `POS`, `QUAL`, `AN`, `MQ`, `DP`, `QD`), subsampled to ~1000 sites. These are the data behind the variant-quality plots in the HTML report. |
| `final_variants.variant_stats.tsv` | Counts of SNPs and indels, both total and `PASS`-only. |

---

## `8_popgen_vcf/`

### `final_variants.clean.vcf_thin1000_maf0.05_maxm0.9.recode.vcf.gz`

Population-genetics VCF produced by vcftools with three filters applied simultaneously:

- **Thinned**: maximum 1 SNP per 1 kb window (reduces linkage between adjacent SNPs)
- **MAF ≥ 0.05**: minor allele frequency filter
- **Max missing ≤ 0.1**: at least 90% genotyping rate per site

This is the input for every analysis in `9_plink/`.

---

## `9_plink/`

Only generated when the corresponding flag is set. All files are derived from the
population-genetics VCF above. Each analysis also writes a PLINK `.log` file recording the exact
command and the number of samples and variants used.

### `--plink_pca`

| File | Description |
|------|-------------|
| `popgen_pca.eigenvec` | Per-sample principal component coordinates. One row per sample; columns `IID`, `PC1`, `PC2`, … |
| `popgen_pca.eigenval` | Eigenvalue of each principal component, in order. Use to compute the variance explained per PC. |

### `--plink_relationships`

Two square, tab-separated matrices describing pairwise relatedness, both computed over the same
samples and variants. Rows and columns follow the order of the accompanying `.id` file.

| File | Description |
|------|-------------|
| `popgen_relationships.rel` | Genomic relationship matrix (GRM) from `--make-rel`: an allele-sharing correlation matrix. Diagonal ≈ 1 (self-relatedness), a parent–child pair ≈ 0.5, unrelated ≈ 0. Negative values are normal and mean a pair is less similar than the sample average. |
| `popgen_relationships.rel.id` | Sample IDs, in the row and column order of `.rel`. |
| `popgen_relationships.king` | KING kinship coefficients from `--make-king`, an identity-by-descent estimate. Diagonal is 0.5 (self-kinship), a parent–child or full-sibling pair ≈ 0.25, second-degree ≈ 0.125, unrelated ≈ 0. More robust than the GRM when population structure is present. |
| `popgen_relationships.king.id` | Sample IDs, in the row and column order of `.king`. |

Use the KING matrix to identify and filter relatives or duplicate samples, and the GRM where a
downstream method expects one (mixed models, heritability, kinship-aware association testing). See
[Configuration](configuration.md#choosing-between-the-two-relationship-matrices) for the full
comparison.

!!! warning "KING requires heterozygous genotypes"
    The KING estimator divides by the heterozygous site count of the less heterozygous sample in
    each pair, so any pair where one sample has no heterozygous calls is reported as `-inf`. This
    covers haploid (`--ploidy 1`) data as well as fully homozygous diploid panels — inbred lines,
    selfing species, clonal isolates — and raising `--ploidy` does not change it. Use the `.rel`
    matrix in those cases.

### `--plink_ld_prune`

| File | Description |
|------|-------------|
| `popgen_ld_pruned.prune.in` | IDs (`chrom:pos`) of variants retained after pruning — an approximately LD-independent subset. |
| `popgen_ld_pruned.prune.out` | IDs of variants removed because they exceeded the r² threshold. |
| `popgen_ld_pruned.vcf.gz` | The population-genetics VCF restricted to the retained variants. Subset from the input VCF, so genotypes, ploidy and all `FORMAT` fields are preserved unchanged. |

---

## `10_reports/`

### `pipeline_report.html`

A self-contained HTML report with three sections:

1. **fastp QC** — stacked bar chart of bases retained vs filtered per sample; line plot of Q20/Q30 rates before and after trimming.
2. **BWA-mem2 mapping** — bubble plot of mapping rate vs total reads; violin plot of the mapping rate distribution.
3. **Variant quality** — density plots for `QUAL`, `AN`, `MQ`, `DP` and `QD` metrics across all variants.

The report uses inline PDF-embedded plots (font-independent) and requires no external dependencies to view.

### Pipeline statistics

| File | Format | Description |
|------|--------|-------------|
| `pipeline_execution_stats.txt` | Human-readable | Per-process-type summary: task count, average/min/max wall-clock time, peak memory. |
| `pipeline_execution_stats.tsv` | TSV | Machine-readable version of the above. Useful for benchmarking and resource optimisation. |
| `pipeline_trace.txt` | TSV | The raw Nextflow execution trace — one row per task, written live during the run. The statistics above are derived from it. |

---

## `11_cnv/`

Only generated with `--cnv`. Copy-number calls from GATK gCNV in cohort mode, for every
short-read sample (see [Configuration](configuration.md#copy-number-variant-calling)).

Every table is sorted by the **contig order of the reference FASTA** (not alphabetically, so
`chr2` comes before `chr10`), then by position. Coordinates are 1-based and inclusive, as in VCF
and GFF. Copy numbers are absolute: with `--ploidy 1`, `0` is a deletion and `2` a duplication;
with `--ploidy 2`, `1` is a heterozygous deletion.

| File | Description |
|------|-------------|
| `cnv_segments.tsv` | Every segment of every sample — the main result. Each sample's genome is cut into runs of bins with the same copy number, so `REF` segments are included; filter on `call` for CNVs only. |
| `cnv_genes.tsv` | Gene × sample copy-number matrix: `gene_id`, `gene_name`, `contig`, `start`, `end`, `strand`, `n_bins`, then one column per sample. `NA` where the gene overlaps no modelled bin. Only with `--cnv_gene_annotation`. |
| `cnv_genes_long.tsv` | One row per gene and sample, with the details behind each value of `cnv_genes.tsv`. Only with `--cnv_gene_annotation`. |
| `cnv_bins.tsv.gz` | Bin × sample copy-number matrix: `contig`, `start`, `end`, then one column per sample. Only the bins that survived filtering. Only with `--cnv_bin_matrix`. |
| `cnv_contig_ploidy.tsv` | Called ploidy of every contig in every sample (`sample`, `contig`, `ploidy`, `ploidy_gq`). Shows aneuploidy and the presence or absence of accessory chromosomes. |
| `cnv_sample_summary.tsv` | Per sample: number and total length of `DEL` and `DUP` segments, how many of them pass `--cnv_min_qs`, and the contigs whose called ploidy differs from `--ploidy`. A sample with far more calls than the rest is usually a noisy library rather than a genuinely unusual genome. |
| `samples/<sample>.cnv_intervals.vcf.gz` | GATK's per-bin calls (`GT`, `CN`, and the copy-number log-posteriors `CNLP`). |
| `samples/<sample>.cnv_segments.vcf.gz` | GATK's per-segment calls, the source of `cnv_segments.tsv`. |
| `samples/<sample>.cnv_denoised_copy_ratios.tsv` | Denoised copy ratio of every bin — coverage relative to the cohort's expectation after removing shared biases. Useful for plotting. |

### `cnv_segments.tsv` columns

| Column | Description |
|--------|-------------|
| `sample`, `contig`, `start`, `end` | Segment location. |
| `call` | `REF`, `DEL` or `DUP`, relative to `--ploidy`. |
| `cn` | Copy number. |
| `n_bins` | Number of bins in the segment. Filtered-out bins inside the segment are not counted, so a segment may span more than `n_bins` × `--cnv_bin_length`. |
| `qa`, `qs`, `qse`, `qss` | gCNV's Phred-scaled segment qualities: that *all* bins (`qa`) or *some* bin (`qs`) support the call, and the quality of the start (`qss`) and end (`qse`) breakpoints. |
| `filter` | `PASS` if `qs` ≥ `--cnv_min_qs`, otherwise `LowQual`. |

### `cnv_genes_long.tsv` columns

A gene's copy number comes from the segments it overlaps.

| Column | Description |
|--------|-------------|
| `sample`, `gene_id`, `gene_name`, `contig`, `start`, `end`, `strand` | Gene, from the annotation. |
| `n_bins` | Modelled bins overlapping the gene. `0` means the gene has no call. |
| `cn` | Copy number covering the largest part of the gene. This is the value in `cnv_genes.tsv`. |
| `cn_min`, `cn_max` | Lowest and highest copy number within the gene. They differ when a breakpoint falls inside it. |
| `frac_altered` | Fraction of the gene's length covered by `DEL` or `DUP` segments. |
| `mean_denoised_cr` | Mean denoised copy ratio of the bins overlapping the gene: a continuous measure, for genes that are too short or too noisy for a confident integer call. |
| `qs_min` | Lowest `qs` of the segments overlapping the gene. |
| `status` | `uniform` (one copy number across the gene), `breakpoint` (a CNV boundary falls inside it) or `no_bins` (no call). |
| `filter` | `PASS` if `qs_min` ≥ `--cnv_min_qs`, otherwise `LowQual`; `NA` for `no_bins`. |
