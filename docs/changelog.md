# Changelog

## v1.1.0 — 2026-09-01

### New features

- **Optional PLINK 2 analyses on the population-genetics VCF.** `--plink_pca` computes a PCA (eigenvectors and eigenvalues), `--plink_relationships` produces GRM and KING relatedness matrices, and `--plink_ld_prune` writes an LD-pruned variant set. Results are published to `9_plink/`.
- **`--help`.** `nextflow run main.nf --help` prints the full parameter list.
- **Multiple input locations.** `--reads` and `--bam_input` accept several patterns separated by a semicolon, e.g. `--reads '/data/runA/*_{1,2}.fq.gz;/data/runB/*_{1,2}.fq.gz'`. A comma cannot be used, as it already means alternation inside a glob.

### Changes

- **All parameters and input files are validated before any task is submitted.** The new `validate_params` module reports every problem in a single block instead of failing partway through a run, and the startup banner gained a `Resolved inputs` section listing the read pairs, BAM files and accessions actually found. All input channels use `checkIfExists`, and both BAM index naming conventions (`sample.bam.bai` and `sample.bai`) are accepted.
- **Outputs are reorganised into numbered directories** following the order of the pipeline: `1_sra_downloads/`, `2_reference/`, `3_fastq_stats/`, `4_bwa_mapping/`, `5_bam_files/`, `6_gvcf_files/`, `7_variants/`, `8_popgen_vcf/`, `9_plink/` and `10_reports/`.
- **`--workdir` removed.** It was never used; set the work directory with Nextflow's own `-work-dir`.

### Improvements

- **Samples dropped during a run are now reported.** Downloading and trimming fall back to an `ignore` strategy once their retries are exhausted, so a failed sample used to disappear silently. The new `ReportIgnoredSamples` process names them in `1_sra_downloads/ignored_samples.txt` and at the top of `pipeline_report.html`.
- **More robust SRA downloads.** A completed `.sra` is reused across retries instead of re-fetched, `prefetch` and `fasterq-dump` timeouts were raised from 10 to 60 minutes, timeouts are distinguished from other failures in the log, `--NCBI_API_key` is now passed to the E-utilities queries, and `SRAresolve` stops the run if no accession resolves to a sequencing run.

---

## v1.0.11 — 2026-07-06

### Changes

- **Samtools and Picard no longer filter out reads before variant calling.** `samtoolsSort` no longer discards alignments below MAPQ 10, and `dupRemoval` now only marks duplicates (`REMOVE_DUPLICATES false`) instead of removing them. All reads are retained in the BAM files.

### New features

- **`--use_duplicate_reads` option.** Disables GATK HaplotypeCaller's default `NotDuplicateReadFilter`, allowing reads flagged as duplicates by `dupRemoval` to be used in variant calling. Useful for reduced-representation sequencing (e.g. ddRAD, RAD-seq) where shared fragment start/end positions are expected and do not indicate PCR duplication.

---

## v1.0.10 — 2026-06-24

### Bug fixes

- **VCF sample names now correctly follow `--SRR_sample_map`.** `GenomicsDBImport` was reassigning names from gVCF filenames, discarding the biological names set by Picard.
- **`filterReference` rewritten as a two-pass streaming parser** to avoid loading the entire genome into RAM.
- **Fixed QC report crash** when sample names share a common prefix (duplicate factor levels in `r_plotting.R`).

### Improvements

- Memory scaling broadened across all processes; `GenomicsDBImport` and `GenotypeGVCFs` start at 16 GB.
- `genomicsdb_batch_size` default raised from 50 → 200.
- Pipeline exits immediately on unrecognised `--params`.
- Added `MergeGVCFs` module for `--keep_gvcf` runs with sub-chromosomal segmentation.

---

## v1.0.9 — 2026-05-13

### Improvements

- **SLURM partition compatibility.** Added `--slurm_queue` parameter (required with `-profile slurm`) to specify the target SLURM partition. The pipeline now exits immediately with a clear error message if this parameter is missing when running on SLURM. The partition should allow a maximum walltime of at least 7 days; shorter limits (1–2 days) may work for small genomes or low-depth sequencing.

---

## v1.0.8 — 2026-05-06

### Bug fixes

- **BAM files are now deleted mid-run after all GATKHC tasks complete.**  
  A new `cleanupBAMs` process receives a count-based sentinel that resolves only after every `GATKHC` task across all intervals has emitted. This guarantees that no BAM is removed while any interval job still needs it, yet reclaims the space as soon as the last GATKHC finishes — without waiting for the full pipeline to succeed. BAMs from `--bam_input` runs are never touched.
- **Fixed zero-length vector crash in `r_process_summary_fastp.R` for SE samples.**  
  `as.numeric(NULL)` produces a zero-length vector, which silently corrupted the summary matrix. Both `duplication$rate` and `insert_size$peak` now use an explicit `length(v) == 0` guard before assignment.

---

## v1.0.7 — 2026-05-05

### New features

- **Replaced `CombineGVCFs` with `GenomicsDBImport` for GVCF consolidation.**  
  The legacy `CombineGVCFs` step has been replaced by GATK's `GenomicsDBImport`, which uses on-disk TileDB storage instead of in-memory merging. This eliminates GC-thrashing at large sample counts (tested at 1,605 samples). Batch size is configurable via `--genomicsdb_batch_size` (default: 50, the Broad production default).

### Compatibility fixes (Nextflow ≥ 26.x)

- `log.info` banner moved inside the `workflow` block — top-level executable statements are no longer permitted in Nextflow 26.x.
- C-style `for (int i = ...)` and `while` loops replaced with Groovy functional expressions (`takeWhile`/`collect`, `.step().each`).
- `${HOME}` environment variable interpolation in `nextflow.config` replaced with `env('HOME')` — bare env-var interpolation was removed in Nextflow 26.x.

### Improvements

- JVM flags `-XX:-UsePerfData --enable-native-access=ALL-UNNAMED` added to all GATK processes to suppress Java 17+ module-restriction warnings and `/tmp/hsperfdata_*` lock conflicts under concurrent Singularity jobs.
- `gatkIndex` base memory increased from 2 GB to 4 GB to prevent a `-Xmx0g` crash on the first attempt.
- Fixed `r_process_summary_fastp.R` crash on single-end samples: `j$insert_size$peak` is `NULL` for SE data; `as.numeric(NULL)` produces a zero-length vector that silently failed the matrix assignment. Now handled with an explicit length check.

---

## v1.0.6 — 2026-04-10

### New features

- **Automatic Singularity image download.**  
  All container images are pulled automatically by Nextflow on the first run — no manual `singularity pull` step is needed. Images are fetched from [quay.io/biocontainers](https://quay.io/organization/biocontainers) and cached in `$HOME/.singularity/cache` (configurable via `singularity.cacheDir`). Subsequent runs reuse the cached images without re-downloading.

- **Bundled example dataset.**  
  The repository ships with a ready-to-run *E. coli* LTEE example (`example/`) that lets you verify your setup end-to-end. Three public SRA samples (SRR2589044, SRR2584863, SRR2584866) mapped against the REL606 reference genome serve as the test case. See [Getting started → Step 4](getting-started.md#step-4-try-the-example-dataset) for instructions.

### Improvements

- Switched all R processes to `rocker/tidyverse:4.4.3` for a reliable, actively maintained R environment.
- Improved QC HTML report: accessible Okabe-Ito colour palette, version and runtime metadata in the header, auto-zoomed BWA mapping-rate axis, violin + jitter distribution plot.
- Fastp JSON summary parsing rewritten with `jsonlite` to correctly separate before- and after-filtering statistics.
- Fixed `geom_vline(linewidth=)` for ggplot2 ≥ 3.5 compatibility.
- Singularity `autoMounts` enabled and environment whitelist added for seamless APPTAINER/SINGULARITY work-directory binding on HPC.
- Pipeline statistics report (`pipeline_statistics.nf`) consolidated from per-process output files.

---

## v1.0.5 and earlier

See the [GitHub commit history](https://github.com/crolllab/genomepanel_nf/commits/main) for changes prior to v1.0.6.
