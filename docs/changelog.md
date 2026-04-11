# Changelog

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
