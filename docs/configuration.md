# Configuration

All parameters are passed on the command line with `--param value`. Boolean flags are set with `true` or `false`.

---

## Execution mode

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-profile` | `string` | `local` | Execution profile. `local` — up to 4 threads per task. `local_highCPU` — up to 24 threads. `slurm` — submit all tasks as SLURM jobs. |
| `-resume` | flag | — | Resume from the last completed step. Requires the `work-dir` to be intact. |
| `-work-dir` | `path` | `./work` | Directory for temporary and intermediate files. Use a fast scratch filesystem for large datasets. |
| `--outdir` | `path` | `./nf_output` | Directory for final output files. |

---

## Read input options

Provide either or both of `--reads` and `--SRA_index`. Alternatively, provide `--bam_input` if you have pre-processed BAM files (can't be combined with `--reads` or `--SRA_index`). See below for details.

### Local FASTQ files

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--reads` | `glob` | — | Glob pattern pointing to paired-end FASTQ files. Must be single-quoted. Accepts paired-end reads only. |

### SRA / ENA accessions

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--SRA_index` | `path` | — | Path to a plain-text file listing NCBI/ENA single or paired-end Illumina read accessions (one per line). Accepts `SRR`, `SRX`, `SRP`, `PRJNA`, `ERR`, etc. |
| `--NCBI_API_key` | `string` | — | **Required with `--SRA_index`.** Your personal [NCBI API key](https://account.ncbi.nlm.nih.gov/). |
| `--SRR_sample_map` | `path` | `false` | CSV file mapping SRR IDs to sample names (`SRR_ID,Sample_Name`). Allows merging multiple runs per sample and renaming samples. See [Getting started](getting-started.md) for format. |

### Pre-processed BAM files

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--bam_input` | `glob` | — | Glob pattern for pre-existing BAM files. Skips all read-processing steps (trimming, mapping, deduplication) and starts directly with variant calling. Cannot be combined with `--reads` or `--SRA_index`. |

!!! warning "BAM file requirements"
    BAM files provided via `--bam_input` must be:

    - Coordinate-sorted
    - Containing `@RG` read group information in the header
    - Accompanied by a `.bai` index file in the same directory

    These requirements are **not validated** by the pipeline — ensure your files comply before running.

---

## Reference genome options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--reference` | `path` | — | **Required.** Absolute path to the reference genome in FASTA format. Must have the `.fasta` extension (not `.fa`, `.fna`, `.fas`). |
| `--reference_segments` | `integer` | `0` | Size in bp of genome segments used for parallel variant calling. `0` disables segmentation. Smaller values increase parallelism at the cost of overhead. |
| `--min_contig_length` | `integer` | `false` | Filter reference contigs shorter than this value (bp). Useful for excluding small scaffolds. `false` disables filtering. |
| `--bwa_index` | `path` | — | Path prefix of pre-built BWA-mem2 index files. Skips BWA indexing. The pipeline expects the index files (`.amb`, `.ann`, `.bwt.2bit.64`, `.pac`, `.0123`) to be co-located with the path prefix. |

---

## Genotyping options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--ploidy` | `integer` | — | **Required.** Ploidy level for GATK HaplotypeCaller. `1` for haploid (fungi, bacteria), `2` for diploid. Higher values can represent pooled samples. |
| `--call_invar_sites` | `boolean` | `false` | When `true`, GATK HaplotypeCaller also emits invariant (monomorphic) sites. Substantially increases output size. Useful for some downstream analyses requiring full genome coverage. |

---

## Output options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--keep_bam` | `boolean` | `false` | When `true`, saves final per-sample BAM files (after duplicate marking) to `<outdir>/bam_files/`. |
| `--keep_gvcf` | `boolean` | `false` | When `true`, saves per-sample GVCF files to `<outdir>/gvcf_files/`. |

---

## SLURM and concurrency

These settings are found in `nextflow.config` and can be edited directly.

| Setting | Default | Description |
|---------|---------|-------------|
| `executor.queueSize` | 300 | Maximum number of tasks submitted to SLURM at once. |
| `executor.submitRateLimit` | `'120/1min'` | Maximum task submission rate (prevents overwhelming the scheduler). |
| SRA download `maxForks` | 10 | Maximum concurrent SRA downloads (PE and SE each). Reduce if NCBI rate-limits your connection. |
| fastp `maxForks` | 20 | Maximum concurrent trimming tasks (PE and SE each; I/O intensive). |
| GATK HC `maxForks` | 150 | Maximum concurrent HaplotypeCaller tasks. |

