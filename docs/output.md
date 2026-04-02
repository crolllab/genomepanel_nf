# Pipeline output

All output files are written to the directory specified by `--outdir` (default: `./nf_output`).

---

## VCF files

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

### `final_variants.thin1000_maf0.05_maxm0.9.recode.vcf.gz`

Population-genetics VCF produced by vcftools with three filters applied simultaneously:

- **Thinned**: maximum 1 SNP per 1 kb window (reduces linkage between adjacent SNPs)
- **MAF ≥ 0.05**: minor allele frequency filter
- **Max missing ≤ 0.1**: at least 90% genotyping rate per site

---

## SRA download logs

These files are only generated when `--SRA_index` is used.

| File | Description |
|------|-------------|
| `NCBI_download_urls.tsv` | Resolved SRR accessions, layout (PE/SE), and download URLs |
| `NCBI_SRR_PE_accessions.txt` | List of all paired-end SRR run IDs |
| `NCBI_SRR_SE_accessions.txt` | List of all single-end SRR run IDs |

---

## QC summary tables

| File | Description |
|------|-------------|
| `fastp_summary.tsv` | Per-sample fastp statistics (reads before/after trimming, Q20/Q30 rates, GC content, etc.). Wide format — one column per sample. |
| `bwa_summary.tsv` | Per-sample BWA-mem2 alignment statistics (total reads, mapped reads, mapping rate, etc.). Wide format — one column per sample. |

---

## HTML quality-control report

### `pipeline_report.html`

A self-contained HTML report with three sections:

1. **fastp QC** — stacked bar chart of bases retained vs filtered per sample; line plot of Q20/Q30 rates before and after trimming.
2. **BWA-mem2 mapping** — bubble plot of mapping rate vs total reads; violin plot of the mapping rate distribution.
3. **Variant quality** — density plots for `QUAL`, `AN`, `MQ`, `DP` and `QD` metrics across all variants.

The report uses inline PDF-embedded plots (font-independent) and requires no external dependencies to view.

---

## Pipeline statistics

| File | Format | Description |
|------|--------|-------------|
| `pipeline_execution_stats.txt` | Human-readable | Per-process-type summary: task count, average/min/max wall-clock time. |
| `pipeline_execution_stats.tsv` | TSV | Machine-readable version of the above. Useful for benchmarking and resource optimisation. |

---

## Per-sample intermediate files (optional)

### `bam_files/`

Saved when `--keep_bam true` is set. Contains per-sample, coordinate-sorted, duplicate-marked BAM files and their `.bai` index files.

```
<sample>_RG_dedup.bam
<sample>_RG_dedup.bam.bai
```

### `gvcf_files/`

Saved when `--keep_gvcf true` is set. Contains per-sample GVCF files emitted by GATK HaplotypeCaller before joint genotyping.

---

## Variant quality plots

### `qual_plots/`

Per-metric quality plots for the unfiltered VCF, saved as individual PDF files and a compressed CSV of the underlying data:

| File | Description |
|------|-------------|
| `final_variants.metrics.csv.gz` | Compressed CSV of all per-variant quality metrics |
| `final_variants.plots.AN.pdf` | Density plot of samples genotyped per site (`AN`) |
| `final_variants.plots.DP.pdf` | Density plot of total read depth (`DP`) |
| `final_variants.plots.MQ.pdf` | Density plot of mapping quality (`MQ`) |
| `final_variants.plots.QD.pdf` | Density plot of quality by depth (`QD`) |
| `final_variants.plots.QUAL.pdf` | Density plot of variant quality score (`QUAL`) |

---

## Per-sample statistics directories

| Directory | Contents |
|-----------|----------|
| `fastp_stats/` | Per-sample fastp JSON and HTML reports |
| `bwa_stats/` | Per-sample BWA-mem2 alignment summary files |
