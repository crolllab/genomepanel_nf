# Configuration

All parameters are passed on the command line with `--param value`. Boolean flags are set with `true` or `false`.

---

## Execution mode

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-profile` | `string` | `local` | Execution profile. `local` — up to 4 threads per task. `local_highCPU` — up to 24 threads. `slurm` — submit all tasks as SLURM jobs (requires `--slurm_queue`). |
| `-resume` | flag | — | Resume from the last completed step. Requires the `work-dir` to be intact. |
| `-work-dir` | `path` | `./work` | Directory for temporary and intermediate files. Use a fast scratch filesystem for large datasets. |
| `--outdir` | `path` | `./nf_output` | Directory for final output files. |
| `--slurm_queue` | `string` | — | **Required with `-profile slurm`.** Name of the SLURM partition to submit all jobs to. The partition should allow a maximum walltime of at least 7 days for large datasets. Shorter limits (1–2 days) may work for smaller genomes or low-depth sequencing, but any job exceeding the partition's walltime limit will fail. |

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
| `--NCBI_API_key` | `string` | — | **Highly recommended with `--SRA_index`.** Get your personal [NCBI API key](https://account.ncbi.nlm.nih.gov/). |
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
| `--reference` | `path` | — | **Required.** Absolute path to the reference genome in FASTA format. Accepts `.fasta`, `.fa`, `.fna`, and `.fas` extensions. |
| `--reference_segments` | `integer` | `0` | Size in bp of genome segments used for parallel variant calling. `0` disables segmentation. Smaller values increase parallelism at the cost of overhead. |
| `--min_contig_length` | `integer` | `false` | Filter reference contigs shorter than this value (bp). Useful for excluding small scaffolds. `false` disables filtering. |
| `--bwa_index` | `path` | — | Path prefix of pre-built BWA-mem2 index files. Skips BWA indexing. The pipeline expects the index files (`.amb`, `.ann`, `.bwt.2bit.64`, `.pac`, `.0123`) to be co-located with the path prefix. |

---

## Genotyping options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--ploidy` | `integer` | — | **Required.** Ploidy level for GATK HaplotypeCaller. `1` for haploid (fungi, bacteria), `2` for diploid. Higher values can represent pooled samples. |
| `--call_invar_sites` | `boolean` | `false` | When `true`, GATK HaplotypeCaller also emits invariant (monomorphic) sites. Substantially increases output size. Useful for some downstream analyses requiring full genome coverage. |
| `--use_duplicate_reads` | `boolean` | `false` | When `true`, disables GATK HaplotypeCaller's `NotDuplicateReadFilter`, so reads flagged as duplicates by the `dupRemoval` process are still used for variant calling. |

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
| `executor.submitRateLimit` | `'240/1min'` | Maximum task submission rate (prevents overwhelming the scheduler). |
| SRA download `maxForks` | 10 | Maximum concurrent SRA downloads (PE and SE each). Reduce if NCBI rate-limits your connection. |
| fastp `maxForks` | 20 | Maximum concurrent trimming tasks (PE and SE each; I/O intensive). |
| GATK HC `maxForks` | 150 | Maximum concurrent HaplotypeCaller tasks. Very I/O intensive. Adjust depending on storage performance. |

!!! note "SLURM partition walltime requirements"
    Several pipeline processes request up to **7 days** of walltime (e.g. BWA mapping, GATK HaplotypeCaller, GenomicsDB import). When using `-profile slurm`, all jobs are submitted to the partition specified with `--slurm_queue`. This partition must allow a maximum walltime sufficient for the longest-running jobs.

    **Recommended:** use a partition with a 7-day (or unlimited) walltime limit.

    **Shorter partitions (1–2 days)** may still work if:

    - Your reference genome is small (e.g. bacteria, fungi)
    - Sequencing depth is low
    - The number of samples is modest

    If a job exceeds the partition's walltime limit, SLURM will kill it and the pipeline will fail at that step. Use `-resume` to restart from the last completed task after switching to a longer partition.

    To list available partitions and their maximum walltimes on your cluster:
    ```bash
    scontrol show partition | grep -E "PartitionName|MaxTime"
    ```
    This prints each partition name alongside its `MaxTime` limit. A value of `UNLIMITED` means no walltime cap.

    Example usage:
    ```bash
    nextflow run main.nf -profile slurm --slurm_queue long [other params]
    ```

