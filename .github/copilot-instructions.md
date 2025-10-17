— end
<!-- genomepanel_nf: AI Coding Agent Instructions -->
# AI Contributor Guide for genomepanel_nf

This repo is a modular Nextflow DSL2 pipeline for large-scale variant calling, optimized for fungal genomes. Follow these conventions for safe, productive contributions:

## Architecture & Data Flow
- **Entry:** `main.nf` → orchestrates `workflows/variant_calling_wf.nf`
- **Processes:** Each step is a separate file in `modules/*.nf` (e.g., `bwa_mapping.nf`, `gatk4_hc.nf`).
- **Containers:** Singularity images in `singularity/`, mapped in `nextflow.config` via `withName:ProcessName` blocks. Always update both if renaming processes/images.
- **Reference:** Must use `.fasta` extension (not `.fa`). Many input patterns depend on `${reference.baseName}.fasta.*`.
- **Parallelization:** Joint genotyping splits by chromosome using the `.fai` index and a `chromosomes_ch` channel. See `workflows/variant_calling_wf.nf` for this pattern.

## Key Patterns & Conventions
- **Safe file cleanup:** Always use this pattern to delete files in process scripts:
  ```bash
  target="$(readlink -f "$file")"
  [ -n "$target" ] && [ -f "$target" ] && rm "$target" || true
  ```
  (Prevents race conditions; see `gatk4_hc.nf` for examples.)
- **Temp directory handling:** CRITICAL - Use `./gatk_tmp` (relative path) for GATK `--tmp-dir`, NOT `$PWD/tmp`. Nextflow creates `NXF_SCRATCH` in `/tmp/nxf.XXXXX` and cd's there, making `$PWD` unreliable. Relative paths work because the scratch dir is bind-mounted into containers.
- **Scratch directory:** `process.scratch = false` in config to avoid `/tmp` space issues. GATK processes generate large outputs that can fill `/tmp`, causing write errors. Running directly in work directory (on `/scratch`) is safer.
  - **Root cause diagnosis:** When `process.scratch = true`, Nextflow creates temporary execution directories in `/tmp/nxf.XXXXX/`. GATK HaplotypeCaller runs successfully for ~53 minutes, processes entire BAM file, but fails at the final write step when attempting to write the compressed GVCF to `/tmp/nxf.XXXXX/sample.g.vcf.gz`. The error is `htsjdk.samtools.util.RuntimeIOException: Write error; BinaryCodec in writemode; file: file:///tmp/nxf.XXXXX/*.g.vcf.gz`. This occurs because the final GVCF (often 50-200MB compressed) cannot be written to `/tmp`, despite `/tmp` having available space (disk not full). The issue appears to be related to NFS-backed `/tmp` write semantics or quota limitations not visible to `df`. Additionally, JVM performance monitoring files (`/tmp/hsperfdata_daniel/*`) can experience locking conflicts when multiple concurrent processes use `/tmp`.
  - **Why retries fail:** Nextflow's retry mechanism (`errorStrategy 'retry', maxRetries 3`) re-executes the task in a new `/tmp/nxf.YYYYY/` directory, but the underlying `/tmp` write issue persists, causing all 3 retries to fail with identical errors after re-processing the entire BAM (~53 minutes each). Solution: `process.scratch = false` forces execution in the work directory (`/scratch/daniel_tmp/XX/YYYYYY/`), avoiding `/tmp` entirely.
- **Error handling:**
  - SRA downloads and long-running steps: `errorStrategy 'ignore'` (allows partial success)
  - Critical steps: `errorStrategy 'retry', maxRetries 3`
- **Channel usage:**
  - Mix local/SRA reads with `.mix()`
  <!-- genomepanel_nf: AI coding agent instructions (concise) -->
  # AI Contributor Guide — genomepanel_nf (short)

  Purpose: quick, actionable rules for automated coding agents working on this Nextflow DSL2 pipeline.

  - Entry point: `main.nf` → `workflows/variant_calling_wf.nf`. Most orchestration lives in the workflow file.
  - Process modules: one process per file under `modules/` (e.g. `gatk4_hc.nf`, `download_SRA.nf`). Keep this modularity.
  - Containers: all Singularity images live in `singularity/` and are mapped to processes in `nextflow.config` using `withName:ProcessName` blocks — never hardcode image paths in modules.

  - Reference requirement: the reference must use a `.fasta` extension (not `.fa`). Many inputs expect `${reference.baseName}.fasta.*` (fai, dict).
  - Chromosome splitting: pipeline parallelizes by chromosome. See `workflows/variant_calling_wf.nf` for the `chromosomes_ch = fai_index.splitCsv(sep: '\t').map { it[0] }` pattern — collect GVCFs before splitting.

  - Critical cleanup pattern (use in process scripts):
    target="$(readlink -f "$file")" && [ -n "$target" ] && [ -f "$target" ] && rm "$target" || true
    Reason: prevents race conditions and avoids failing processes if files are already removed. See `modules/gatk4_hc.nf`.

  - GATK / tmp rules (must-follow):
    - Use relative tmp dirs for GATK (e.g. `--tmp-dir ./gatk_tmp`) — do NOT rely on `$PWD/tmp` or system `/tmp`.
    - `process.scratch = false` is used to avoid writing large outputs into NFS-backed `/tmp` (see `nextflow.config`).

  - SRA download specifics (implemented in `modules/resolve_SRA.nf` + `modules/download_SRA.nf`):
    - Try ENA direct URLs first (fast, `.fastq.gz`), fallback to NCBI `prefetch` + `fasterq-dump`.
    - When using `prefetch`, use `--output-file` (not `--output-directory`). For `fasterq-dump`, set `TMPDIR` and use `-t` for temp dir. Example pattern is in repo docs and `download_SRA.nf`.

  - Process conventions:
    - Use `tag` with descriptive text (e.g., `tag "GATK4 HaplotypeCaller"`).
    - Critical processes: `errorStrategy 'retry', maxRetries 3`. Non-critical (long downloads): `errorStrategy 'ignore'`.
    - Use `tuple val(sample_id), path(files)` for tracking samples through channels.

  - Adding a new process: create `modules/my_process.nf`, add a `withName:MyProcess` block in `nextflow.config`, and `include { MyProcess } from '../modules/my_process'` in `workflows/variant_calling_wf.nf`.

  - Quick run examples:
    - Local test: `nextflow run main.nf -profile local_highCPU -work-dir /tmp/nf_test --reference IPO323.fasta --ploidy 1 --reads 'test/*_{1,2}.fq.gz'`
    - Production (SLURM): `NCBI_API_KEY=... nextflow run main.nf -config nextflow.config -profile slurm -work-dir /scratch/nf_tmp --outdir ./output --reference ref.fasta --ploidy 1 --reads '/path/**_{1,2}.fq.gz' --SRA_index SRA_accessions.txt`

  - Debugging pointers:
    - Check `.nextflow.log` for orchestration messages. Search for `Ignored process` to find downloads that failed.
    - Inspect `work/<hash>/` for `.command.log` and `.command.err` for process-level failures.

  - Key files to read when making code changes: `main.nf`, `workflows/variant_calling_wf.nf`, `nextflow.config`, `modules/download_SRA.nf`, `modules/gatk4_hc.nf`.

  If anything here is unclear or you want more examples (e.g., exact `fasterq-dump` invocation used), tell me which section to expand and I will iterate.

