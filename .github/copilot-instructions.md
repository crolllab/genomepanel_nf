# Nextflow Genomics Pipeline Instructions

## Project Overview
`genomepanel_nf` is a Nextflow DSL2 pipeline for variant calling on large genome panels. It processes Illumina paired-end/single-end reads from local files or NCBI SRA, performs BWA mapping, GATK HaplotypeCaller variant calling, and quality filtering. The pipeline is optimized for fungal genomes (specifically _Zymoseptoria tritici_) and supports both local and SLURM execution.

## Architecture & Data Flow

### Modular Structure
- **Main entry**: `main.nf` → `workflows/variant_calling_wf.nf`
- **Process modules**: `modules/*.nf` (22 separate process definitions)
- **Container config**: `nextflow.config` binds each process to a Singularity container
- **Execution profiles**: `local` (4 CPUs), `local_highCPU` (24 CPUs), `slurm` (8 CPUs per task)

### Pipeline Stages (Sequential)
1. **SRA Resolution & Download** (optional) → PE/SE fastq files
2. **Fastp Trimming** → trimmed fastq pairs
3. **BWA-mem2 Mapping** → SAM files
4. **Samtools Sort + Picard (AddRG → MarkDuplicates)** → deduplicated BAM files
5. **GATK HaplotypeCaller** → per-sample GVCF files
6. **Chromosome-parallel Variant Calling**:
   - CombineGVCFs → per-chromosome combined GVCF
   - GenotypeGVCFs → per-chromosome VCF
   - FilterVCFs → per-chromosome filtered VCF
   - CleanVCFs → per-chromosome clean VCF
7. **BCFtools Concat** → final VCFs (`final_variants.vcf.gz`, `final_variants.clean.vcf.gz`)
8. **VCFtools** → thinned/MAF-filtered VCF for population genetics
9. **R Reporting** → quality plots and summary tables

### Critical Parallelization Pattern
The pipeline splits by chromosome after GVCF creation (step 5). The `fai_index` is split by `\t` to create `chromosomes_ch`, which feeds parallel GATK processes. This is the primary scalability mechanism.

## Nextflow DSL2 Conventions

### Channel Patterns
- **Input mixing**: Local + SRA reads are merged using `.mix()` before trimming
  ```groovy
  combined_pe_ch = sra_pe_formatted.mix(local_pe_formatted)
  ```
- **Collect before chromosome split**: GVCFs are collected with `.collect()` before splitting by chromosome
  ```groovy
  gvcf_ch = gvcf.collect()
  cgvcf = CombineGVCFs(gvcf_ch, chromosomes_ch, ...)
  ```
- **Tuple format**: Processes use `tuple val(sample_id), path(files)` for sample tracking

### Process Conventions
- **Tag directive**: Always includes descriptive names (e.g., `tag "GATK4 HaplotypeCaller"`)
- **Error handling**: Critical processes use `errorStrategy 'retry', maxRetries 3`; non-critical use `errorStrategy 'ignore'`
- **Conditional publishing**: Uses `enabled: params.keep_bam_gvcf` to optionally save BAM/GVCF files
- **Resource cleanup**: Processes actively delete input files after processing via `rm "\$(readlink -f "$file")"` to manage disk space during large runs
- **Container binding**: Each process has a `withName:ProcessName` block in `nextflow.config` specifying its Singularity container

### File Naming Convention
- Processes output files named `${sample_id}_suffix.ext` (e.g., `${sample_id}.g.vcf.gz`)
- Index files follow the pattern `${reference.baseName}.fasta.fai`, `${reference.baseName}.dict`

## Key Parameters & Usage

### Required Parameters
- `--reference`: Path to reference genome (.fasta extension required, not .fa)
- `--ploidy`: Numeric value (1 for haploid, 2 for diploid)
- `--NCBI_API_key`: Required only if using `--SRA_index`
- One of: `--reads` (local fastq glob pattern) OR `--SRA_index` (file with SRA accessions)

### Glob Pattern for Local Reads
Use single quotes with complex brace expansions:
```bash
--reads '/path/**_{,R}{1,2}{,_001,_001_*}.{fq,fastq}.gz'
```
This matches Illumina naming variations (_1/_2, _R1/_R2, with/without _001 suffix).

### Critical Execution Patterns
```bash
# Standard SLURM execution
nextflow run main.nf -config nextflow.config -profile slurm \
  -work-dir '/scratch/nf_tmp' --outdir './output' \
  --reference ref.fasta --ploidy 1 \
  --reads '/path/**_{1,2}.fq.gz' \
  --NCBI_API_key $KEY --SRA_index accessions.txt
```

### Common Gotchas
- **Screen/tmux required**: Nextflow orchestrator must stay alive even with SLURM (it manages job submission)
- **Reference file extension**: Must be `.fasta` (not `.fa`) due to hardcoded `${reference.baseName}.fasta.*` patterns
- **Temp directory**: Use `-work-dir '/scratch/...'` for large datasets; work directory can be multi-TB
- **Resume behavior**: `-resume` requires intact work directory; deleted work files break resumption

## Development Patterns

### Adding New Processes
1. Create `modules/new_process.nf` with process definition
2. Add container config in `nextflow.config`:
   ```groovy
   withName:NewProcess {
       container = './singularity/tool%3Aversion--hash'
   }
   ```
3. Include in `workflows/variant_calling_wf.nf`: `include { NewProcess } from '../modules/new_process'`
4. Call process in workflow, respecting channel types

### Testing Local Changes
Use `-profile local_highCPU` with small dataset:
```bash
nextflow run main.nf -profile local_highCPU -work-dir '/tmp/nf_test' \
  --reference small_ref.fasta --ploidy 1 --reads 'test/*_{1,2}.fq.gz'
```

### Debugging Failed Processes
- Check `.nextflow.log` for high-level errors
- Inspect `work/<hash>/` directories for process-specific logs (`.command.log`, `.command.err`)
- Enable debug mode: `process.debug = true` in `nextflow.config`

## Container Management

### Singularity Image Naming
Images use URL-encoded names: `tool%3Aversion--hash` (`:` encoded as `%3A`)

### Sourcing Images
Preferred: Copy from `/legserv/Temp/Shared/genomepanel_nf/singularity`
Alternative: Pull from Galaxy Project depot (see README.md)

### Custom Container Bindings
`nextflow.config` includes:
```groovy
runOptions = "-B /tmp/$USER:/tmp/$USER"
envWhitelist = 'APPTAINERENV_NXF_TASK_WORKDIR,SINGULARITYENV_NXF_TASK_WORKDIR'
```
Mount additional paths if processes need access to external data.

## Output Files

### Primary Outputs (in `--outdir`)
- `final_variants.vcf.gz`: All variants with GATK filter flags
- `final_variants.clean.vcf.gz`: Only PASS variants
- `final_variants.thin1000_maf0.05_maxm0.9.recode.vcf.gz`: Thinned for population genetics
- `fastp_summary.tsv`, `bwa_summary.tsv`: Aggregate QC metrics
- `qual_plots/`: PDF plots for variant quality metrics (AN, DP, MQ, QD, QUAL)

### Conditional Outputs (if `--keep_bam_gvcf true`)
- `bam_files/`: Per-sample deduplicated BAMs
- `gvcf_files/`: Per-sample GVCFs

## Special Considerations

### Memory Management
Large runs use aggressive file cleanup (`rm "\$(readlink -f "$file")"` in process scripts) to avoid filling work directories. Do not remove these cleanup commands.

### Chromosome Splitting
GATK processes operate per-chromosome for parallelization. To modify this:
1. Change how `chromosomes_ch` is created in `workflows/variant_calling_wf.nf`
2. Ensure downstream processes handle the new granularity
3. Update memory allocations (per-chromosome processes need less memory than whole-genome)

### SRA Download Failure Handling
`modules/download_SRA.nf` implements graceful failure handling to prevent pipeline aborts:
- **No pipeline abort**: Failed downloads use `errorStrategy 'ignore'` and `exit 0` to continue pipeline
- **3 retry attempts**: Each download attempts 3 times with 30-second pauses
- **Timeouts**: prefetch (5 min) and fasterq-dump (10 min) prevent hanging
- **Status marker files**: Every download creates `.download_status` (SUCCESS/FAILED) + dummy fastq files for failures
- **Explicit filtering**: Workflow uses `.filter()` on status file content to exclude failures with `log.warn` messages
- **No optional outputs**: All processes emit exactly 3 outputs (srr, fastq, status) to prevent silent data loss
- **Complete accounting**: `NCBI_download_summary.tsv` tracks all input SRR accessions (successes + failures)
- **Critical**: Never use `optional: true` on SRA download outputs - it causes silent sample loss during channel mixing
