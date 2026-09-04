# Resource requirements

Resource directives for every process in `modules/`, as actually configured.
`time`, `cpus`, `memory` and `maxForks` come from the `withName:` blocks in
`nextflow.config`; `errorStrategy` and `maxRetries` come from the process
definitions in `modules/`.

Memory written as `N GB × attempt` is a closure (`{ N.GB * task.attempt }`): the
request grows with each retry, so a task killed for running out of memory comes
back with more. A task that needs more than the ladder reaches should have its
base value raised rather than its retry count.

### Input resolution and reference indexing

| Process | Time | CPUs | Memory | maxForks | errorStrategy | maxRetries |
|---------|------|------|--------|----------|---------------|------------|
| `SRAresolve` | 7d | 1 | 1 GB | — | `retry` | 6 |
| `SRAdownloadPE` | 7d | 1 | 2 GB × attempt | 10 | `retry` → **`ignore`** after attempt 4 | 6 |
| `SRAdownloadSE` | 7d | 1 | 2 GB × attempt | 10 | `retry` → **`ignore`** after attempt 4 | 6 |
| `ReportIgnoredSamples` | 1h | 1 | 1 GB × attempt | — | `retry` | 6 |
| `loadBAMs` | 1h | 1 | 1 GB × attempt | — | `retry` | 6 |
| `probeBAMSample` | 1h | 1 | 1 GB × attempt | — | `retry` | 6 |
| `filterReference` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `bwaIndex` | 1d | 1 | 16 GB × attempt | — | `retry` | 6 |
| `fastaIndex` | 1d | 1 | 2 GB × attempt | — | `retry` | 6 |
| `gatkIndex` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |

### Read processing and mapping

| Process | Time | CPUs | Memory | maxForks | errorStrategy | maxRetries |
|---------|------|------|--------|----------|---------------|------------|
| `trimSequencesPE` | 1d | — | 2 GB × attempt | 20 | `retry` → **`ignore`** after attempt 3 | 6 |
| `trimSequencesSE` | 1d | — | 2 GB × attempt | 20 | `retry` → **`ignore`** after attempt 3 | 6 |
| `bwaMap` | 7d | — | 8 GB × attempt | — | `retry` | 6 |
| `samtoolsSort` | 1d | 1 | 2 GB × attempt | — | `retry` | 6 |
| `addRG` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `mergeRunBAMs` | 1d | 2 | 4 GB × attempt | — | `retry` | 6 |
| `mergeRunBAMsBamInput` | 1d | 2 | 4 GB × attempt | — | `retry` | 6 |
| `dupRemoval` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `dupRemovalMergedBamInput` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `cleanupBAMs` | 1h | 1 | 256 MB | — | — | — |

`mergeRunBAMsBamInput` and `dupRemovalMergedBamInput` are the same processes as
`mergeRunBAMs` and `dupRemoval`, included under an alias so the `--bam_input`
path (several caller-supplied BAMs sharing one `@RG SM` tag) can run them a
second time, independently of the read-processing path's own merge/dedup step.
See gp_wf.nf.

### Variant calling

| Process | Time | CPUs | Memory | maxForks | errorStrategy | maxRetries |
|---------|------|------|--------|----------|---------------|------------|
| `GATKHC` | 7d | 1 | 4 GB × attempt | 500 | `retry` | 6 |
| `GenomicsDBImport` | 7d | 2 | 16 GB × attempt | 150 | `retry` on OOM (137/143/247), else **`finish`** | 6 |
| `GenotypeGVCFs` | 7d | 1 | 16 GB × attempt | 150 | `retry` on OOM (137/143/247), else **`finish`** | 6 |
| `MergeGVCFs` | 1d | 1 | 2 GB × attempt | — | `retry` | 6 |

### VCF post-processing

| Process | Time | CPUs | Memory | maxForks | errorStrategy | maxRetries |
|---------|------|------|--------|----------|---------------|------------|
| `FilterVCFs` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `CleanVCFs` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `ConcatVCFs` | 7d | 1 | 2 GB × attempt | — | `retry` | 6 |
| `ConcatCleanVCFs` | 7d | 1 | 2 GB × attempt | — | `retry` | 6 |
| `PopGenVCF` | 7d | 1 | 1 GB × attempt | — | `retry` | 6 |

### Population genetics (opt-in)

| Process | Time | CPUs | Memory | maxForks | errorStrategy | maxRetries |
|---------|------|------|--------|----------|---------------|------------|
| `PlinkPCA` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `PlinkRelationships` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |
| `PlinkLDPrune` | 1d | 1 | 4 GB × attempt | — | `retry` | 6 |

### Summaries and reporting

| Process | Time | CPUs | Memory | maxForks | errorStrategy | maxRetries |
|---------|------|------|--------|----------|---------------|------------|
| `RSummarizingFASTP` | 1h | 1 | 1 GB × attempt | — | `retry` | 6 |
| `RSummarizingBWA` | 1h | 1 | 1 GB × attempt | — | `retry` | 6 |
| `RQualPlotting` | 24h | 1 | 16 GB × attempt | — | `retry` | 6 |
| `PipelineStatistics` | 4h | 1 | 1 GB × attempt | — | `retry` | 6 |

---

## Notes

### CPUs marked "—"

`trimSequencesPE`, `trimSequencesSE` and `bwaMap` set no `cpus` directive, so they
inherit the profile default: **4** under `-profile local`, **8** under
`-profile slurm`, **16** under `-profile local_highCPU`. `bwaMap` passes this to
`bwa-mem2 mem -t`, so the mapping thread count follows the profile.

### Processes that give up instead of failing the run

Four processes fall back to `ignore` once their retries are exhausted. The task
fails, the run continues, and the sample is **absent from the final VCF** while
the pipeline still reports success:

| Process | Gives up after |
|---------|----------------|
| `SRAdownloadPE`, `SRAdownloadSE` | attempt 4 |
| `trimSequencesPE`, `trimSequencesSE` | attempt 3 |

Dropped samples are named in `<outdir>/1_sra_downloads/ignored_samples.txt` and in
the **Sample completeness** section of the HTML report, both written by
`ReportIgnoredSamples`. Check one of them before treating a run as complete.

`GenomicsDBImport` and `GenotypeGVCFs` retry **only** on out-of-memory exit
statuses (137, 143, 247); anything else is a GATK user error that a retry will
not fix (most commonly two gVCFs claiming the same sample name), and now
`finish` — not `ignore` — lets already-running tasks complete but stops the
workflow and reports failure, rather than dropping the interval from the
final VCF while reporting success (the 2026-09-04 lepus incident: 85 tasks
failed this way and were ignored 85 times).

### The SRA download retry loop

`SRAdownloadPE`/`SRAdownloadSE` also retry *inside* the task, independently of
Nextflow's `maxRetries`. Each Nextflow attempt runs up to 4 internal attempts
with backoffs of 10, 30 and 60 minutes (plus jitter), trying ENA first and
falling back to NCBI `prefetch` + `fasterq-dump`. Both sra-tools steps are
wrapped in a 3600 s `timeout`; raise `prefetch_timeout` / `fasterq_timeout` in
`modules/download_SRA.nf` for unusually large accessions. A completed `.sra` is
kept between internal attempts so a failed extraction does not re-download it.

One Nextflow attempt can therefore take a couple of hours, most of it sleeping.

### Unused module

`modules/combine_gvcfs.nf` (`CombineGVCFs`) is not included by any workflow and
has no `withName:` block. It is dead code and is intentionally absent above.

### Keeping this file accurate

The tables were derived from the code, not written by hand, and they go stale as
soon as a `withName:` block or a process directive changes. When updating, read
the values back out of `nextflow.config` and `modules/*.nf` rather than editing
individual cells — the previous version of this file had drifted to the point of
listing the wrong memory for six processes and the wrong `maxRetries` for nearly
all of them.
