# HPC usage & utilities

## Notes on HPC execution

### Storage requirements

The pipeline aggressively deletes intermediate files after each step to minimise disk usage (`cleanup = true` in `nextflow.config`). Despite this, large runs can temporarily require **many TB** of scratch space. Always point `-work-dir` to a fast, high-capacity scratch filesystem:

```bash
nextflow run main.nf ... -work-dir '/path/to/scratch/genomepanel_work'
```

!!! warning
    Because intermediate files are removed on task completion, `-resume` may not skip many steps once variant calling is underway. It is most useful for resuming after the reference indexing stage.

### Memory for the Nextflow process itself

For large runs, the Java VM managing Nextflow can require significant memory. Set the heap size before running:

```bash
export NXF_OPTS='-Xms8g -Xmx64g'
```

Keep the Nextflow process alive in a `tmux` or `screen` session — even when using `--profile slurm`, the Nextflow process must remain running until all jobs complete.

### SLURM time limits

All SLURM tasks request a **7-day** time limit by default. If your cluster enforces shorter queue limits, edit the `time` directive in the relevant module files (e.g. `modules/bwa_mapping.nf`).

### Concurrency and rate limits

The following `maxForks` settings in `nextflow.config` prevent overloading storage and compute:

| Process | Default `maxForks` | Notes |
|---------|-------------------|-------|
| SRA download | 10 | NCBI will throttle or block connections with too many parallel downloads (PE and SE separately) |
| fastp trimming | 20 | Very I/O-intensive; reduce if storage I/O is a bottleneck (PE and SE separately) |
| GATK HaplotypeCaller | 150 | High parallelism; reduce if the scheduler struggles under load |

The executor is also rate-limited at 300 queued tasks and 120 submissions per minute (`executor.queueSize`, `executor.submitRateLimit`).

---

## Utilities

### Download SRA files manually

If `sra-tools` encounters connection resets or other SRA-side errors, download files manually with `fastq-dump` and use `--reads` instead:

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

Use `bcftools reheader` with a two-column whitespace-delimited lookup table:

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
nextflow run main.nf -config nextflow.config -profile slurm \
  --reference $REF --ploidy 1 \
  --bam_input '/path/to/bams/*_RG_dedup.bam'
```

Requirements for input BAMs:

- Coordinate-sorted (use `samtools sort -o` or equivalent)
- `@RG` read group in the header (`picard AddOrReplaceReadGroups`)
- `.bai` index in the same directory (`samtools index`)
