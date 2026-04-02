# Resource Requirements

Resource directives for active Nextflow processes in `modules/`. Dynamic memory values scale with `task.attempt`.

| Process | Time | CPUs | Memory | errorStrategy | maxRetries |
|---------|------|------|--------|---------------|------------|
| `bwaIndex` | 1d | 1 | `8.GB * task.attempt` | retry | 3 |
| `CleanVCFs` | 1d | 1 | `2.GB * task.attempt` | retry | 3 |
| `ConcatVCFs` | 1d | 1 | `2.GB * task.attempt` | retry | 3 |
| `trimSequencesPE` | 1d | — | `2.GB * task.attempt` | retry→ignore ¹ | 3 |
| `trimSequencesSE` | 1d | 4 | `2.GB * task.attempt` | retry→ignore ¹ | 3 |
| `filterReference` | 1d | — | `4.GB * task.attempt` | retry | 3 |
| `FilterVCFs` | 1d | 1 | `4.GB * task.attempt` | retry | 3 |
| `gatkIndex` | 1d | 1 | `4.GB * task.attempt` | retry | 3 |
| `fastaIndex` | 1d | 1 | `2.GB * task.attempt` | retry | 3 |
| `addRG` | 1d | 1 | `8.GB * task.attempt` | retry | 3 |
| `dupRemoval` | 1d | 1 | `8.GB * task.attempt` | retry | 3 |
| `PopGenVCF` | 1d | 1 | 1 GB | retry | 3 |
| `samtoolsSort` | 1d | 1 | `2.GB * task.attempt` | retry | 3 |
| `loadBAMs` | 1h | 1 | 1 GB | retry | 3 |
| `RSummarizingBWA` | 1h | 1 | 1 GB | retry | 3 |
| `RSummarizingFASTP` | 1h | 1 | 1 GB | retry | 3 |
| `RQualPlotting` | 24h | 1 | 16 GB | retry | 3 |
| `PipelineStatistics` | 4h | 1 | 1 GB | retry | 3 |
| `bwaMap` | 7d | — | `16.GB * task.attempt` | retry | 3 |
| `CombineGVCFs` | 7d | 1 | `4.GB * task.attempt` | retry | 3 |
| `ConcatCleanVCFs` | 7d | 1 | `4.GB * task.attempt` | retry | 3 |
| `SRAdownloadPE` | 7d | 1 | 4 GB | retry→ignore ¹ | 4 |
| `SRAdownloadSE` | 7d | 1 | 4 GB | retry→ignore ¹ | 4 |
| `GATKHC` | 7d | 1 | `4.GB * task.attempt` | retry | 3 |
| `GenotypeGVCFs` | 7d | 1 | `8.GB * task.attempt` | retry | 3 |
| `SRAresolve` | 7d | 1 | 1 GB | retry | 3 |

**Notes:**

1. `SRAdownloadPE` and `SRAdownloadSE` use `{ task.attempt <= 4 ? 'retry' : 'ignore' }` with `maxRetries 4` and exponential backoff (0s, 2s, 4s, 8s).
2. `trimSequencesPE` and `trimSequencesSE` use `{ task.attempt <= 3 ? 'retry' : 'ignore' }` with `maxRetries 3` and exponential backoff (0s, 2s, 4s).
