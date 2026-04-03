![alt text](https://github.com/crolllab/genomepanel_nf/blob/main/logo.png?raw=true)

Pipeline to variant call large genome panels
========================================

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19392838.svg)](https://doi.org/10.5281/zenodo.19392838)

## Table of Contents

1. [Overview](#overview)
2. [Step 1: Repository, singularity and nextflow environment](#step-1-repository-singularity-containers-and-nextflow-environment)
   - [Singularity images](#get-singularity-images)
3. [Step 2: Configure genomepanel_nf options](#step-2-configure-genomepanel_nf-options)
4. [Step 3: Run genomepanel_nf - example options](#step-3-run-genomepanel_nf---example-options)
   - [Obtain the reference genome](#obtain-the-zymoseptoria-tritici-ipo323-reference-genome)
   - [Select local fastq files](#select-sets-of-local-fastq-file-pairs)
   - [Define SRA/ENA accessions](#define-ncbi-sra-accessions)
5. [Step 4: genomepanel_nf run example](#step-4-genomepanel_nf-run-example)
6. [Step 5: Pipeline output](#step-5-pipeline-output)
7. [Description of pipeline steps](#description-of-pipeline-steps)
8. [Features to consider / bug fixes](#features-to-consider--bug-fixes)
9. [Notes on HPC usage](#notes-on-hpc-usage)
10. [Utilities](#utilities)
   - [Download SRA files manually](#download-sra-files-manually)
   - [Rename samples in final vcf](#rename-samples-in-final-vcf)

---

## Overview

The `genomepanel_nf` Nextflow pipeline performs highly efficient reference genome mapping, SNP calling and quality checks. The pipeline accepts either locally stored Illumina fastq files, SRA accessions numbers or both simultaneously. The pipeline can be run locally or through the SLURM queuing system. Analyses are split by chromosome (and segments) for improved parallelization. Intermediate files are aggressively cleaned to allow large datasets to be processed with limited disk space.

## Release notes

### v1.0.5
- Improved module resource requests: `CleanVCFs` base memory raised from 2 GB to 4 GB, preventing GATK JVM heap underrun on large intervals.
- Improved process label readability: shortened `tag` strings across multiple modules for cleaner Nextflow log output.
- Fixed HTML QC report generation: R plotting and summary scripts are now supplied as external files rather than here-documents, resolving character-escaping issues that could silently corrupt the report.
- SRA downloader (`download_SRA.nf`): pinned `sra-tools` to 3.2.1 (3.4.1 has known segfaults); replaced deprecated `--output-file` with `--output-directory`; added `timeout 600` to `prefetch` and `fasterq-dump`; added exponential backoff retry delays (10 min / 30 min / 60 min) with random jitter.

### v1.0.4b
- Fixed invalid `retryStrategy` process directive in `download_SRA.nf` and `fastp_trimming.nf` that caused a pipeline startup error with Nextflow ≥25.x.

### v1.0.4
- Added GitHub Pages documentation site at https://crolllab.github.io/genomepanel_nf/

### v1.0.3
- Updated all Singularity container images to latest Galaxy depot releases: sra-tools 3.4.1, fastp 1.3.1, bwa-mem2 2.3, samtools 1.23.1, bcftools 1.23.1, gatk4-spark 4.6.2.0 (build rev 1).
- Redesigned QC report (`pipeline_report.html`): unified fastp, BWA and variant quality sections into a single HTML report with inline PDF plots (font-independent, works in all containers and browsers).
- Optimized SLURM resource requests across all pipeline modules.

---

## Step 1: Repository, singularity and nextflow environment

**NB: Step 1 can be skipped on LEGcompute by using `module load genomepanel_nf`**

Cloning the repository 
```bash
git clone git@github.com:crolllab/genomepanel_nf.git
cd genomepanel_nf
```

Activate the nextflow module (if available on your system)

```bash
module load Nextflow
```

Alternatively, create a conda environment for Nextflow

```bash
micromamba create -n nf_gp_env
micromamba activate nf_gp_env
micromamba install -c bioconda nextflow
```

### Singularity images
The `singularity` folder must be in the same directory as the `main.nf` file.

You can pull the images directly from the Galaxy Project depot.

```bash
mkdir -p singularity
cd singularity
# entrez-direct
singularity pull https://depot.galaxyproject.org/singularity/entrez-direct:24.0--he881be0_0
# sratools
singularity pull https://depot.galaxyproject.org/singularity/sra-tools%3A3.2.1--h4304569_1
# fastp
singularity pull https://depot.galaxyproject.org/singularity/fastp%3A1.3.1--h43da1c4_0
# bwa
singularity pull https://depot.galaxyproject.org/singularity/bwa-mem2%3A2.3--he70b90d_0
# samtools
singularity pull https://depot.galaxyproject.org/singularity/samtools%3A1.23.1--ha83d96e_0
# picard
singularity pull https://depot.galaxyproject.org/singularity/picard%3A3.4.0--hdfd78af_0
# gatk
singularity pull https://depot.galaxyproject.org/singularity/gatk4-spark%3A4.6.2.0--hdfd78af_1
# bcftools
singularity pull https://depot.galaxyproject.org/singularity/bcftools%3A1.23.1--hb2cee57_0
# R with tidyverse
singularity pull https://depot.galaxyproject.org/singularity/r-tidyverse%3A1.2.1
# vcftools
singularity pull https://depot.galaxyproject.org/singularity/vcftools%3A0.1.17--pl5321h077b44d_0
```

(For Croll lab users: a copy of the compatible images is on the file server)

```bash
rsync -va /legserv/Temp/Shared/genomepanel_nf/singularity .
```


---

## Step 2: Configure `genomepanel_nf` options  

### Available parameters

_Run options:_

- `-profile`: Optional. `local` runs tasks locally with up to 4 threads each. `local_highCPU` runs tasks with up to 24 threads each. `slurm` submits all tasks as SLURM jobs. Default: `local`.

- `-resume`: Optional. If set, the pipeline will resume from the last completed step, skipping already completed steps. The `work-dir` needs to be intact for this. This is particularly useful if e.g. the reference genome indexing was already completed in a previous run. Note that `genomepanel_nf` aggressively cleans up temporary files to save space, so resuming may not always be saving computation time.

- `-work-dir`: Optional. Defines where to store temporary files (often many TB). Consider `/scratch/work` for large datasets. Default: `./work`. 

- `--outdir`: Optional. Folder to save final output files. Default: `./nf_output`.


_Read input options:_

- `--reads`: Optional. Provide the path to the folder containing the fastq read files. The pipeline will automatically find all paired read files based on the naming convention. Must be bracketed by single quotes `'`. See below for examples. Important: accepts only paired-end reads.

- `--SRA_index`: Optional. Instead of local fastq files, you can provide a file listing NCBI SRA accessions (or ENA, etc.) with one accession per line including `SRR...`, `SRP...`, `SRX...`, `PRNJ...`, etc. If the accession includes multiple `SRR...` runs, all included runs are processed. You can use the [SRA Explorer](https://sra-explorer.info) to collect accession ids. 

  Important:
  - Accepts only paired-end reads locally. Both SE and PE are accepted from SRA.
  - If the download from SRA produces errors (connection reset, etc.), an alternative is to download the files separately, and use the `--reads` option to specify the downloaded files. See below for an example of how to download SRA files manually.

- `--bam_input`: Optional. **Alternative entry point**: Provide a glob pattern to pre-existing BAM files to skip read processing steps (SRA download, trimming, mapping, duplicate marking) and start directly with variant calling. This is useful when you have already processed BAM files from another pipeline or a previous run. Must be bracketed by single quotes `'`. Cannot be used together with `--reads` or `--SRA_index`. Sample names are extracted from BAM filenames, automatically removing `_RG_dedup` suffix if present.

  **Requirements for BAM files:**
  - BAM files must be coordinate-sorted
  - BAM files must contain read group (@RG) information in the header
  - Each BAM file must have a corresponding `.bai` index file in the same directory
  - These requirements are NOT validated by the pipeline - ensure your files meet these criteria before running
  
  Example:
  ```bash
  # Process all BAM files in a directory
  --bam_input '/path/to/bams/*.bam'
  
  # Process specific samples
  --bam_input '/path/to/bams/sample_{A,B,C}_RG_dedup.bam'
  ```

- `--SRR_sample_map`: Optional. A CSV file mapping SRR accession IDs to sample names. This allows multiple SRR accessions to be assigned to the same sample name, which is useful when a sample was sequenced multiple times and should be genotyped as a single combined dataset. The CSV format is: `SRR_ID,Sample_Name` (one mapping per line, no header). This process can also be used to rename samples. If an SRR ID is not listed in the file, the original SRR ID will be used as the sample name. Default: `false` (no mapping). The repository includes an example file `sample_map.csv`. Note: This option only applies when using `--reads` or `--SRA_index`, not with `--bam_input`.

  Example `sample_map.csv`:
  ```
  SRR1234567,Sample_A
  SRR1234568,Sample_A
  SRR1234569,Sample_B
  SRR1234570,Sample_C
  ```
  In this example, `SRR1234567` and `SRR1234568` will both be assigned to `Sample_A` during genotyping. The repository includes an example file `sample_map.csv`.


_NCBI SRA download configuration:_

- `--NCBI_API_key`: Required for querying and downloading from NCBI SRA. You can get your key by creating an [account on NCBI](https://account.ncbi.nlm.nih.gov/). After registration/login, find on the top right the link to the "Account settings". Click on "Create API key" and copy it.


_Reference genome options:_

- `--reference`: Required. Provide a reference genome fasta file with an absolute path and make sure the file has the `.fasta` extension (not `.fa`, `.fna`or `.fas`).

- `--reference_segments`: Optional. Size of genome segments (in base pairs) used for parallel processing during variant calling. Smaller values increase parallelization but add overhead. Larger values reduce parallelism but minimize overhead. You can de-activate segmentation by setting the value to `0`. Default: `0` (no segmentation).

- `--min_contig_length`: Optional. Filter reference contigs shorter than this value (in base pairs). Useful for excluding small scaffolds or contigs from variant calling. Default: `false` (no filtering).

- `--bwa_index`: Optional. Provide the path prefix to pre-built BWA-mem2 index files. This skips the BWA indexing step, saving time and computational resources with very big genomes. The path should point to the reference prefix (e.g., `/path/to/ref.fasta` if the above option was specified with `--reference /path/to/ref.fasta`). The pipeline will automatically find the associated index files (`.amb`, `.ann`, `.bwt.2bit.64`, `.pac`, `.0123`). 


_Genotyping option:_

- `--ploidy`: Required. Use `1` for haploid genomes, `2` for diploid genomes. Can also be used to define higher ploidy levels in pooled samples.

- `--call_invar_sites`: If set to `true`, GATK HaplotypeCaller will call invariant sites in addition to variant sites. This increases output file size significantly but may be useful for certain downstream analyses. Default: `false`.


_Output options:_

- `--keep_bam`: If set to `true`, per-sample BAM files will be saved to the output directory. Default: `false`.

- `--keep_gvcf`: If set to `true`, per-sample GVCF files will be saved to the output directory. Default: `false`.

---

## Step 3: `genomepanel_nf` configuration example

The example below is based on the wheat pathogen _Zymoseptoria tritici_ IPO323 reference genome and Illumina paired-end reads from local file servers and NCBI SRA. Substitute reference genome, NCBI accessions and local read paths with your own data.

### Obtain the reference genome

```bash
# Obtain reference genome from Ensembl Fungi
wget http://ftp.ensemblgenomes.org/pub/fungi/current/fasta/zymoseptoria_tritici/dna/Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
gunzip Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
mv Zymoseptoria_tritici.MG2.dna.toplevel.fa IPO323.fasta
```

### Select local fastq files

The following examples show different ways to select paired-end fastq files. The `--reads` option must be bracketed by single quotes `'`. The examples assume that the read files are named according to the Illumina convention, i.e. ending with `_1.fq.gz` and `_2.fq.gz` or `_R1.fq.gz` and `_R2.fq.gz`. Adjust the patterns according to your own naming conventions.

```bash
# Option 1 - select all fastq files ending with _1.fq.gz and _2.fq.gz
--reads '/path/to/reads/*{1,2}.fq.gz'

# Option 2 - select all fastq files ending with _1.fq.gz and _2.fq.gz, including all subdirectories (** instead of *)!
--reads '/path/to/reads/**{1,2}.fq.gz'

# Option 3 - select all files ending with _1.fq.gz and _2.fq.gz OR ending with _R1.fq.gz and _R2.fq.gz
--reads '/path/to/reads/*_{,R}{1,2}.fq.gz'

# Option 4 - select all files (including all subdirectories), with optional variation in fq/fastq, 1/R1 (2/R2), optional _001 or _001_ additions
--reads '/path/to/reads/**_{,R}{1,2}{,_001,_001_*}.{fq,fastq}.gz'
```


### Define SRA/ENA accessions

Example file to provide for the `--SRA_index ...` option. Note that different accession types are accepted, including `PRJNA...`, `SRP...`, `SRX...`, and `SRR...`. The pipeline will automatically resolve all included `SRR...` run accessions.

```bash
PRJNA250875
SRR4235096
ERR13824535
```

Save the text file e.g. as `SRA_accessions.txt`. The repository includes an example file.

---

## Step 4: `genomepanel_nf` run example

```bash
# example input reference genome (see above how to obtain it)
REF=$PWD/IPO323.fasta

# read pairs ending with _1.fq.gz and _2.fq.gz in the /path/to/reads/ folder
READS='/path/to/reads/*_{1,2}.fq.gz'
```


### Pipeline run

Start the pipeline using `slurm` and processing local fastq files and NCBI accessions. Temporary files are written to `/scratch` and the output will be in the `my_nf_run_output` folder. The `SRA_accessions.txt` example file is included in the repository.

```bash
# substitute with your own NCBI API key!
NCBI_API_KEY=abcdef1234567890

# make sure nextflow is available (module load or micromamba)

# run nextflow pipeline
export NXF_OPTS='-Xms8g -Xmx64g'
nextflow run main.nf -config nextflow.config -profile slurm \
  -work-dir '/scratch/my_nf_tmp' --outdir './my_nf_run_output' \
  --NCBI_API_key $NCBI_API_KEY \
  --reference $REF --ploidy 1 \
  --reads $READS \
  --SRA_index './SRA_accessions.txt'
```


### Notes on the exection:
- Before executing the `nextflow` command, enter e.g. a `tmux` or `screen` session. The session needs to remain active until the end of the pipeline (even if you specify the `slurm` option)
- In `local` and `local_highCPU` modes, the pipeline will run on the local machine. Use the `slurm` option to spread the load to all available nodes (requires SLURM).

---
  
## Step 5: Pipeline output

The pipeline will produce the following output files in the specified `--outdir`:

VCF including all identified variants, quality flags according to GATK VariantFiltration.
```bash
final_variants.vcf.gz
```

VCF including only variants passing the GATK VariantFiltration criteria.
```bash
final_variants.clean.vcf.gz
```

Thinned VCF (1 SNP per kb), MAF > 0.05 and high genotyping rate (> 90 genotyping rate).
```bash
final_variants.thin1000_maf0.05_maxm0.9.recode.vcf.gz
```

Text files listing the SRR accessions and NCBI/ENA download URLs used for single-end and paired-end reads, respectively.
```bash
NCBI_download_urls.tsv
NCBI_SRR_PE_accessions.txt
NCBI_SRR_SE_accessions.txt
```

TSV files summarizing `fastp` and `bwa-mem2` statistics for all samples.
```bash
fastp_summary.tsv
bwa_summary.tsv
```

A graphical report with some key sample and variant quality metrics.
```bash
pipeline_report.html
```

Pipeline execution statistics with completion times for all process types.
```bash
pipeline_execution_stats.txt       # Human-readable formatted report
pipeline_execution_stats.tsv       # Machine-readable tab-separated format
```

The pipeline statistics files include:
- Process name and description (e.g., "BWA Mapping", "GATK HaplotypeCaller")
- Complete task counts for each process type
- Average execution time (wall-clock duration)
- Minimum and maximum execution times
- Useful for identifying bottlenecks, optimizing resources, and documenting pipeline performance


### Additional output folders:
- `bam_files/`: If `--keep_bam_gvcf true` is set, contains per-sample BAM files after marking duplicates.
- `gvcf_files/`: If `--keep_bam_gvcf true` is set, contains per-sample GVCF files.
- `fastp_stats/`: Per-sample `fastp` quality control statistics in JSON format.
- `bwa_stats/`: Per-sample `bwa-mem2` mapping statistics in JSON format.
- `qual_plots/`: Analysis of variant quality metrics of all identified variants, including plots for `AN` (samples genotyped), `DP` (read depth), `MQ` (mapping quality), `QD` (quality by depth), and `QUAL` (global quality score). The metrics are saved in a compressed CSV file and the plots in PDF format.

```bash
final_variants.metrics.csv.gz
final_variants.plots.AN.pdf
final_variants.plots.DP.pdf
final_variants.plots.MQ.pdf
final_variants.plots.QD.pdf
final_variants.plots.QUAL.pdf
```

---

## Description of pipeline steps

1. `fastp` is run with default settings, a summary tsv file is produced at the end.
2. `bwa-mem2` is run with default settings, a summary tsv file is produced at the end.
3. `gatk` Haplotypecaller emits GVCF, you need to set `--ploidy` (see above)
4. `gatk` VariantFiltration flags low quality variants based on the following criteria: `QD<20.0`, `MQ<30.0`,`ReadPosRankSum <-2.0 | >2.0`, `MQRankSum <-2.0 | >2.0` and `BaseQRankSum <-2.0 | >2.0`. No filtering based on `QUAL` values as these are sample size dependent.
5. `bcftools` is used to produce a high-quality variants file including only variants passing the GATK VariantFiltration criteria.
6. Variant quality metrics are plotted using an R script.
7. `vcftools` is used to produce a a thinned (1 SNP per kb), MAF > 0.05 and high genotyping rate (> 90 genotyping rate) VCF file.

---

## Features to consider / bug fixes
- include GATK CNV calling
- run basic pop gen analyses (e.g. PCA, admixture)

---

## Notes on HPC usage
- The pipeline is designed to minimize storage space by deleting intermediate files after each step. However, this means that resuming the pipeline may not be possible.
- Despite aggressive temporary file cleanup, the pipeline can still require a large amount of storage space (often many TB) during execution. If space becomes an issue, consider using more aggressive `maxForks` settings in the `nextflow.config` file to reduce the number of parallel tasks. Reduce first the download, trim and mapping concurrency.
- For very large pipeline runs, make sure that the node on which the executor runs has enough memory overhead (e.g. 20-30 GB) as a surge in task execution could lead to pipeline failures.
- Make sure the `work-dir` is on a fast storage system with enough space to store temporary files (often many TB).
- With the `slurm` profile, all tasks request a 7-day time limit. If this is not optimal for available queues on the HPC system, consider adjusting the time limits in each task file. 
- Execution of new task is rate limited to no overwhelm a system. Look for the executor configuration in `nextflow.config` in the `nextflow.config` file.
- SRA downloads are capped at 10 parallel downloads to avoid stalling by NCBI. You can adjust this limit in the `nextflow.config` with the `maxForks` option. 
- The trimming step with fastp is also rate limited to 20 parallel tasks as these can be very I/O intensive. Adjust this limit in the `nextflow.config` with the `maxForks` option.
- Similarly, the GATK HaplotypeCaller step is rate limited to 100 parallel tasks to avoid overwhelming the system. Adjust this limit in the `nextflow.config` with the `maxForks` option.

---

## Utilities

### Download SRA files manually

Use conda/micromamba to install the `sratools` package, which includes the `fastq-dump` command.

Create the following file e.g. `SRA_download.sh` with one accession per line:

```bash
#!/bin/bash
fastq-dump --split-files --gzip SRR24910574
fastq-dump --split-files --gzip SRR24910575
fastq-dump --split-files --gzip SRR25074049
fastq-dump --split-files --gzip SRR25074050
...
```

Parallelize the download using GNU parallel:

```bash
parallel -j 10 < SRA_download.sh
```

NB: Don't try to download too many files at once, as NCBI will stall you.

Proceed with `genomepanel_nf` as described above, using the `--reads` option to point to the download folder.

### Rename samples in final vcf  

```bash
bcftools reheader --samples id_lookup.txt input.vcf.gz -Oz > output_reheadered.vcf.gz ;

# id_lookup.txt (space-delimited):
oldname1 newname1
oldname2 newname2
oldname3 newname3
oldname4 newname4
```

