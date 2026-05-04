# Changelog

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
