# HPC usage & utilities

## Notes on HPC execution

### Storage requirements

The pipeline aggressively deletes intermediate files after each step to minimise disk usage (`cleanup = true` in `nextflow.config`). Despite this, large runs can temporarily require **many TB** of scratch space. Always point `-work-dir` to a fast, high-capacity scratch filesystem:

```bash
nextflow run main.nf ... -work-dir '/path/to/scratch/genomepanel_work'
```

!!! warning
    Because intermediate files are removed on task completion, `-resume` may not skip many steps once variant calling is underway. It is most useful for resuming after the reference indexing stage.

Keep the Nextflow process alive in a `tmux` or `screen` session — even when using `--profile slurm`, the Nextflow process must remain running until all jobs complete.

### SLURM time limits

All SLURM tasks request a **7-day** time limit by default. If your cluster enforces shorter queue limits, edit the `time` directive in the relevant module files (e.g. `modules/bwa_mapping.nf`).

### Singularity / Apptainer

**Image cache** — by default, images are pulled to `$HOME/.singularity/cache`. Worker nodes must have read access to this path. If `/home` is not shared across nodes, set `cacheDir` in the `singularity {}` block of `nextflow.config` to a path on a shared filesystem:

```groovy
singularity {
    cacheDir = "/scratch/$USER/.singularity/cache"
}
```

**Bind mounts** — on clusters running Apptainer (the successor to Singularity), automatic bind-mounting can be disabled by the sysadmin via `/etc/apptainer/apptainer.conf` (`mount hostfs = no`). If tasks fail with "file not found" errors inside the container, add explicit bind paths in `nextflow.config`:

```groovy
singularity.runOptions = "--bind /scratch,/data"
```

---

### Concurrency and rate limits

Three settings in `nextflow.config` govern how much work the pipeline puts on the scheduler:

| Setting | Default | Applies to |
|---------|---------|------------|
| `executor.queueSize` | 500 | All processes combined |
| `executor.submitRateLimit` | `'500/1min'` | All processes combined |
| `maxForks` | per process, see below | A single process |

**All three count tasks that are submitted but not yet complete — not tasks that are running.** A task waiting in the SLURM queue and a task running on a node draw on the same budget. That distinction is what the defaults are built around, and overlooking it is the most common reason a run leaves cores idle.

#### Keep a backlog pending

If these limits are set to the number of jobs the cluster will actually run, then in the steady state every slot holds a *running* job and the SLURM queue holds nothing PENDING. Each time a job finishes, its core sits idle until Nextflow notices the completion — it polls every 5 seconds by default — submits a replacement, and the scheduler places it. On a busy cluster that turnaround measures around 2 seconds on average, occasionally 15 seconds or more.

For hour-long tasks this is irrelevant. For tasks lasting seconds to a minute, which is exactly what HaplotypeCaller produces on small contigs, it wastes a noticeable fraction of every core.

The remedy is to keep `maxForks` and `queueSize` comfortably **above** the concurrency the cluster will grant, so the surplus queues up as PENDING. SLURM then starts the next task on a freed core immediately, without a round trip through Nextflow. Because `queueSize` caps `maxForks`, raising either one alone has no effect — set both.

A reasonable starting point is 1.5× the number of cores you expect to be allocated for the run. There is no benefit to a queue deeper than the remaining work, and a very large backlog from a single user is worth checking against local scheduler etiquette.

#### Per-process limits

`maxForks` additionally protects resources that are not the CPU:

| Process | Default `maxForks` | Notes |
|---------|-------------------|-------|
| SRA download | 10 | NCBI will throttle or block connections with too many parallel downloads (PE and SE separately) |
| fastp trimming | 20 | Very I/O-intensive; reduce if storage I/O is a bottleneck (PE and SE separately) |
| GATK HaplotypeCaller | 500 | The pipeline's widest stage; reduce if the scheduler or the storage struggles under load |

#### Submission rate

`submitRateLimit` exists to avoid flooding the scheduler with `sbatch` calls, which on a shared cluster affects every user. It binds only when tasks are both numerous and short: sustaining *C* tasks in flight whose mean duration is *D* seconds requires *C/D* submissions per second. The default `'500/1min'` (8.3 per second) therefore sustains 500 concurrent tasks averaging 60 seconds each. Below that duration at full concurrency, the rate limit rather than `queueSize` becomes the constraint, and you would need to raise it.

#### Task duration and `--reference_segments`

With the default `--reference_segments 0`, HaplotypeCaller is scattered one task per contig, so task duration follows contig length. On a genome with a few large chromosomes and many small scaffolds this is extremely skewed. On one 160-sample fungal panel, two thirds of the HaplotypeCaller tasks finished within a minute and together accounted for 1% of the compute, while the slowest 10% ran for over an hour and accounted for 75% of it; the single longest task ran for 10 hours.

Raising `maxForks` cannot help with that shape, because the stage cannot finish before its longest task. Setting `--reference_segments` (for example `1000000` for 1 Mb windows) splits the large contigs into comparable pieces, which shortens the tail and is usually the larger wall-clock win. The trade-off is more tasks, each with its own scheduling and container-startup overhead, and a `MergeGVCFs` step for `--keep_gvcf` runs.

---

## Utilities

### Download SRA files manually

If `sra-tools` encounters connection resets or other SRA-side errors, download files manually with `fastq-dump` and use `--reads` to pass the downloaded files instead:

```bash
# Install sra-tools via micromamba
micromamba install -c bioconda sra-tools

# Create a download script (one accession per fastq-dump call)
cat > SRA_download.sh << 'EOF'
#!/bin/bash
fastq-dump --split-files --gzip SRR24910574
fastq-dump --split-files --gzip SRR24910575
fastq-dump --split-files --gzip SRR25074049
EOF

# Parallelise the download (limit to 10 concurrent)
parallel -j 10 < SRA_download.sh
```

!!! tip
    Do not exceed ~10 parallel downloads; NCBI will stall the connection.

Then run the pipeline pointing to the downloaded files:

```bash
nextflow run main.nf ... --reads '/path/to/downloads/*{1,2}.fastq.gz'
```

---

### Rename samples in the final VCF

Note that you can define custom names among the configuration options. 

If you need to change sample names in the final VCF, use `bcftools reheader` with a two-column whitespace-delimited lookup table:

```bash
bcftools reheader --samples id_lookup.txt input.vcf.gz -Oz > output_reheadered.vcf.gz
```

Format of `id_lookup.txt` (space-delimited, one mapping per line):

```
oldname1 newname1
oldname2 newname2
oldname3 newname3
```

---

### Use a BAM entry point for existing data

If you have already-processed BAM files (e.g., from a previous pipeline run), you can skip all read-processing steps:

```bash
nextflow run main.nf -config nextflow.config \
  --reference $REF --ploidy 1 \
  --bam_input '/path/to/bams/*_RG_dedup.bam'
```

Requirements for input BAMs:

- Coordinate-sorted (use `samtools sort -o` or equivalent)
- `@RG` read group in the header (`picard AddOrReplaceReadGroups`)
- `.bai` index in the same directory (`samtools index`)
