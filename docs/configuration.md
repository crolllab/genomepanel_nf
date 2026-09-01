# Configuration

All parameters are passed on the command line with `--param value`. Boolean flags are set with `true` or `false`.

Run `nextflow run main.nf --help` for a summary of every parameter.

---

## Startup validation

Every parameter is checked before the pipeline submits a single task, and all problems
are reported together in one block. In particular, each path and glob pattern is resolved
at startup, so a `--reads`, `--bam_input` or `--reference` pattern that matches no files is
a **fatal error** rather than a run that completes without producing any variants.

The startup banner also reports what each input resolved to, which is the quickest way to
confirm the pipeline sees the data you expect:

```
   Resolved inputs
       Reference      : ecoli_REL606.fasta (4.5 MB)
       Local FASTQ    : 6 files -> 3 read pairs
       Sample map     : 9 run IDs -> 6 sample names
```

Non-fatal issues — files with no mate, accession lines that do not look like accessions,
flag combinations with no effect — are reported as `WARN` lines above the banner and do
not stop the run.

---

## File paths and glob patterns

`--reads` and `--bam_input` take **glob patterns**; `--reference` and `--SRA_index` take a
single file. The rules below apply to all of them.

### Quoting

**Always use single quotes around a glob pattern.**

| Form | Works? | What happens |
|------|--------|--------------|
| `--reads 'data/*_{1,2}.fastq.gz'` | ✅ **Use this** | The pattern reaches Nextflow intact and Nextflow expands it. |
| `--reads "data/*_{1,2}.fastq.gz"` | ⚠️ Usually | The shell does not glob-expand inside double quotes, so this normally behaves identically — but `$` and `` ` `` are still interpreted, so a path containing them breaks. |
| `--reads data/*_{1,2}.fastq.gz` | ❌ **Silently wrong** | The **shell** expands the pattern first. `--reads` receives only the *first* file and Nextflow discards the rest. |

The unquoted form is the dangerous one, because nothing about it looks wrong:

```bash
# The shell turns this ...
--reads data/*_{1,2}.fastq.gz
# ... into this, and only the first path is kept:
--reads data/A_1.fastq.gz data/B_1.fastq.gz data/A_2.fastq.gz data/B_2.fastq.gz
```

The pipeline detects this: any argument left unattached to a parameter is reported as an
error naming the parameter that swallowed it, together with the files that were dropped.
A quoted pattern is never at risk, so single-quoting is the habit worth keeping.

No quoting is needed for a plain path with no wildcard in it, such as
`--reference /data/genome.fasta`, though quoting does no harm.

### Reading from several locations

Give **one quoted value** and separate the patterns with a **semicolon**:

```bash
--reads 'runA/*_{1,2}.fastq.gz;runB/*_{1,2}.fastq.gz'
--bam_input 'batch1/*.bam;batch2/*.bam'
```

Files matched by all the patterns are pooled into a single set of samples, and duplicates
matched by more than one pattern are counted once. The startup banner reports the total, so
you can confirm every location was picked up.

!!! warning "A comma is not a separator"
    A comma already means alternation *inside* a glob — the `{1,2}` in `*_{1,2}.fastq.gz` —
    so it cannot also separate patterns. `path1,path2`, `path1|path2` and `path1 path2` are
    each rejected at startup with a message pointing at the semicolon form.

`--reference` and `--SRA_index` accept exactly one file each; a pattern matching several
files is rejected.

---

## Execution mode

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-profile` | `string` | `local` | Execution profile. `local` — up to 4 threads per task. `local_highCPU` — up to 24 threads. `slurm` — submit all tasks as SLURM jobs (requires `--slurm_queue`). |
| `-resume` | flag | — | Resume from the last completed step. Requires the `work-dir` to be intact. |
| `-work-dir` | `path` | `./work` | Directory for temporary and intermediate files. Use a fast scratch filesystem for large datasets. Note the single dash — `--workdir` is not a pipeline parameter and the pipeline will tell you so. |
| `--help` | flag | — | Print all parameters with their defaults and exit. |
| `--outdir` | `path` | `./nf_output` | Directory for final output files. |
| `--slurm_queue` | `string` | — | **Required with `-profile slurm`.** Name of the SLURM partition to submit all jobs to. The partition should allow a maximum walltime of at least 7 days for large datasets. Shorter limits (1–2 days) may work for smaller genomes or low-depth sequencing, but any job exceeding the partition's walltime limit will fail. |

---

## Read input options

Provide either or both of `--reads` and `--SRA_index`. Alternatively, provide `--bam_input` if you have pre-processed BAM files (can't be combined with `--reads` or `--SRA_index`). See below for details.

### Local FASTQ files

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--reads` | `glob` | — | Glob pattern pointing to paired-end FASTQ files. Accepts paired-end reads only. Single-quote the pattern; separate several locations with `;`. See [File paths and glob patterns](#file-paths-and-glob-patterns). |

### SRA / ENA accessions

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--SRA_index` | `path` | — | Path to a plain-text file listing NCBI/ENA single or paired-end Illumina read accessions (one per line). Accepts `SRR`, `SRX`, `SRP`, `PRJNA`, `ERR`, etc. |
| `--NCBI_API_key` | `string` | — | **Highly recommended with `--SRA_index`.** Passed to E-utilities as `NCBI_API_KEY`, raising the metadata lookup rate limit from 3 to 10 requests/second. Get your personal [NCBI API key](https://account.ncbi.nlm.nih.gov/). |
| `--SRR_sample_map` | `path` | `false` | CSV file mapping SRR IDs to sample names (`SRR_ID,Sample_Name`, no header). Allows merging multiple runs per sample and renaming samples. Must be comma-separated — a tab-separated file is rejected at startup, because sample names are looked up by comma and every lookup would silently miss. See [Getting started](getting-started.md) for format. |

### Pre-processed BAM files

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--bam_input` | `glob` | — | Glob pattern for pre-existing BAM files. Skips all read-processing steps (trimming, mapping, deduplication) and starts directly with variant calling. Cannot be combined with `--reads` or `--SRA_index`. Single-quote the pattern; separate several locations with `;`. See [File paths and glob patterns](#file-paths-and-glob-patterns). |

!!! warning "BAM file requirements"
    BAM files provided via `--bam_input` must be:

    - Coordinate-sorted
    - Containing `@RG` read group information in the header
    - Accompanied by a `.bai` index file in the same directory (either `sample.bam.bai` or `sample.bai`)

    The **index is checked at startup** and every BAM missing one is listed in a single error.
    Coordinate sorting and the presence of `@RG` headers are *not* validated — ensure your
    files comply before running.

---

## Reference genome options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--reference` | `path` | — | **Required.** Absolute path to the reference genome in FASTA format, uncompressed. Accepts `.fasta`, `.fa`, `.fna`, and `.fas` extensions. Exactly one file — not a pattern. |
| `--reference_segments` | `integer` | `0` | Size in bp of genome segments used for parallel variant calling. `0` disables segmentation. Smaller values increase parallelism at the cost of overhead. |
| `--min_contig_length` | `integer` | `false` | Filter reference contigs shorter than this value (bp). Useful for excluding small scaffolds. `false` disables filtering. |
| `--bwa_index` | `path` | — | Path to a pre-built BWA-mem2 index, given as **the FASTA path the index was built from** — normally the exact same value as `--reference`. Skips BWA indexing. See the warning below. |

!!! warning "`--bwa_index` takes the FASTA path, not an index file"
    `bwa-mem2 index ref.fasta` writes its five files by appending suffixes to the
    FASTA name: `ref.fasta.amb`, `ref.fasta.ann`, `ref.fasta.bwt.2bit.64`,
    `ref.fasta.pac`, `ref.fasta.0123`.

    The pipeline rebuilds those names the same way — by appending each suffix to
    whatever you pass. So the value must be the **FASTA path itself**:

    ```bash
    # correct - same value as --reference
    --reference reference/genome.fasta \
    --bwa_index reference/genome.fasta
    ```

    Pointing at one of the index files instead is the common mistake, and it
    fails in a way that is hard to read:

    ```bash
    # WRONG - do not point at an index file
    --bwa_index reference/genome.fasta.bwt.2bit.64
    ```

    That makes the pipeline look for `genome.fasta.bwt.2bit.64.amb`,
    `genome.fasta.bwt.2bit.64.bwt.2bit.64` and so on. None exist, so Nextflow
    stages broken symlinks and **every mapping task fails** with:

    ```
    ERROR! Unable to open the file: <reference>.bwt.2bit.64
    ```

    If you see that message, check `--bwa_index` first. The index files must all
    sit in the same directory as the FASTA.

    Omit `--bwa_index` entirely to have the pipeline build the index itself.

---

## Genotyping options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--ploidy` | `integer` | — | **Required.** Ploidy level for GATK HaplotypeCaller. `1` for haploid (fungi, bacteria), `2` for diploid. Higher values can represent pooled samples. |
| `--call_invar_sites` | `boolean` | `false` | When `true`, GATK HaplotypeCaller also emits invariant (monomorphic) sites. Substantially increases output size. Useful for some downstream analyses requiring full genome coverage. |

---

## Population-genetics analyses

Optional PLINK analyses run at the very end of the pipeline, on the population-genetics VCF
(thinned, MAF- and missingness-filtered). Each is off by default and enabled with its own flag.
All results are written to `<outdir>/9_plink/`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--plink_pca` | `boolean` | `false` | Principal component analysis (PLINK 2, `--pca`). Up to 10 PCs, automatically capped at *n* samples − 1. |
| `--plink_relationships` | `boolean` | `false` | Pairwise relatedness between all samples. Runs **both** `--make-rel` (GRM) and `--make-king` (KING kinship) in PLINK 2, as the two answer different questions — see below. |
| `--plink_ld_prune` | `boolean` | `false` | Linkage-disequilibrium pruning (PLINK 2, `--indep-pairwise 50 5 0.5`), plus the pruned VCF. |

### Choosing between the two relationship matrices

`--plink_relationships` produces two square matrices over the same samples and variants. They are
not interchangeable:

| | `--make-rel` → `.rel` | `--make-king` → `.king` |
|---|---|---|
| **Estimates** | Genomic relationship matrix (GRM): an allele-sharing correlation matrix between individuals, based on identity by state | KING kinship coefficients: an identity-by-descent estimate of the co-segregation of alleles from shared ancestors |
| **Scale** | Correlation-like. Self-relatedness ≈ 1; a parent–child pair ≈ 0.5 | Kinship. Self-kinship = 0.5; a parent–child pair ≈ 0.25; unrelated ≈ 0 |
| **Needs allele frequencies** | Yes — supplied by the pipeline via `--read-freq` | No — derived internally |
| **Population structure** | Sensitive. The zero-mean and variance normalisation is computed across the whole sample, so strong structure dominates the estimates and distorts familial relationships | Robust. Preferred when population structure is present or unaccounted for |
| **Use it for** | Mixed models, heritability, kinship-aware association testing — anything expecting a GRM | Identifying relatives and filtering duplicates or close kin before analysis |

Following the [PLINK 2 relatedness tutorial](https://www.cog-genomics.org/plink/2.0/tutorials/qc2b),
prefer the KING matrix for relationship filtering whenever population structure may be unaccounted
for. The pipeline writes complete symmetric matrices (`square`) rather than the tutorial's
half-filled `square0`, so they load directly into R or Python without symmetrising.

Both matrices are computed from the population-genetics VCF, which vcftools has already filtered to
MAF ≥ 0.05. Relatedness estimation needs reasonably common variants — empirical minor allele
frequencies are reliable down to roughly *n*<sup>−0.5</sup> — so no further MAF filter is applied.

!!! warning "KING requires heterozygous genotypes"
    The KING estimator divides by the heterozygous site count of the *less heterozygous* member of
    each pair. Any pair in which one sample has no heterozygous calls therefore comes out as `-inf`,
    and the `.king` matrix carries no information for that pair.

    This affects haploid (`--ploidy 1`) data — where heterozygotes cannot exist — but also fully
    homozygous diploid panels such as inbred lines, selfing species and clonal isolates. **Raising
    `--ploidy` does not fix it:** calling a haploid organism as diploid yields `0/0` and `1/1`
    genotypes with essentially no heterozygotes, and the matrix stays `-inf`.

    The `.rel` (GRM) matrix remains well defined in all of these cases and is the one to use. The
    pipeline emits a warning at startup when `--ploidy 1` is combined with this analysis; the
    homozygous-diploid cases cannot be detected up front, so check the `.king` matrix for `-inf`
    before relying on it.

!!! note "Small panels"
    PLINK 2 declines to estimate allele frequencies and LD from fewer than 50 samples. The pipeline
    works around this by supplying allele frequencies computed from the panel itself (`--read-freq`)
    for PCA, and by passing `--bad-ld` for LD pruning. Both analyses therefore complete on small
    panels, but the resulting estimates should be treated with caution.

---

## Output options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--keep_bam` | `boolean` | `false` | When `true`, saves final per-sample BAM files (after duplicate marking) to `<outdir>/5_bam_files/`. |
| `--keep_gvcf` | `boolean` | `false` | When `true`, saves per-sample GVCF files to `<outdir>/6_gvcf_files/`. |

---

## Advanced options

Minor, rarely-needed settings for special use cases.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--use_duplicate_reads` | `boolean` | `false` | When `true`, disables GATK HaplotypeCaller's `NotDuplicateReadFilter`, so reads flagged as duplicates by the `dupRemoval` process are still used for variant calling. By default, duplicate-flagged reads are excluded from calling. |
| `--genomicsdb_batch_size` | `integer` | `200` | Number of samples GATK `GenomicsDBImport` loads per batch (`--batch-size`). The default is high enough that a typical panel imports in a single pass, which is the fastest option. Lower it to reduce peak memory on very large panels — smaller batches hold fewer samples open at once, at the cost of extra passes over the interval. |

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

