![alt text](https://github.com/crolllab/genomepanel_nf/blob/main/logo.png?raw=true)

Pipeline to variant call large genome panels
========================================

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
9. [Utilities](#utilities)
   - [Download SRA files manually](#download-sra-files-manually)
   - [Rename samples in final vcf](#rename-samples-in-final-vcf)

---

## Overview

The `genomepanel_nf` Nextflow pipeline performs reference genome mapping, SNP calling and quality checks. The pipeline accepts either locally stored Illumina fastq files, SRA accessions numbers or both simultaneously. The pipeline can be run locally or through the SLURM queuing system. Analyses are split by chromosome for improved parallelization. 

**Implemented steps:**
- `entrez-direct`: query NCBI SRA for metadata (optional)
- `sratools`: download SRA files (optional)
- `fastp`: quality control
- `bwa-mem2`: read mapping
- `samtools`: sorting, indexing, and merging
- `picard`: mark duplicates
- `gatk`: HaplotypeCaller and joint genotyping
- `gatk`: VariantFiltration and quality score plotting
- `vcftools`: VCF filtering and subsetting
- Pipeline statistics: automatic execution time analysis for all process types

**Current limitations:**
- If a sample is represented by multiple SRA accessions or fastq file pairs, the datasets are not combined into a single variant call. 
---

## Step 1: Repository, singularity and nextflow environment

Cloning the repository, 
```bash
git clone git@github.com:crolllab/genomepanel_nf.git
cd genomepanel_nf
```

Create a conda environment for Nextflow

```bash
micromamba create -n nf_gp_env
micromamba activate nf_gp_env
micromamba install -c bioconda nextflow
```

### Singularity images
The `singularity` folder must be in the same directory as the `main.nf` file.

A copy of the compatible images is on LEGserv.

```bash
rsync -va /legserv/Temp/Shared/genomepanel_nf/singularity .
```

Alternatively, you can pull the images directly from the Galaxy Project depot.

```bash
mkdir -p singularity
cd singularity
# entrez-direct
singularity pull https://depot.galaxyproject.org/singularity/entrez-direct:24.0--he881be0_0
# sratools
singularity pull https://depot.galaxyproject.org/singularity/sra-tools%3A3.2.1--h4304569_1
# fastp
singularity pull https://depot.galaxyproject.org/singularity/fastp%3A0.24.1--heae3180_0
# bwa
singularity pull https://depot.galaxyproject.org/singularity/bwa-mem2%3A2.2.1--he70b90d_8
# samtools
singularity pull https://depot.galaxyproject.org/singularity/samtools%3A1.22.1--h96c455f_0
# picard
singularity pull https://depot.galaxyproject.org/singularity/picard%3A3.4.0--hdfd78af_0
# gatk
singularity pull https://depot.galaxyproject.org/singularity/gatk4-spark%3A4.6.2.0--hdfd78af_0
# bcftools
singularity pull https://depot.galaxyproject.org/singularity/bcftools%3A1.21--h8b25389_0
# R with tidyverse
singularity pull https://depot.galaxyproject.org/singularity/r-tidyverse%3A1.2.1
# vcftools
singularity pull https://depot.galaxyproject.org/singularity/vcftools%3A0.1.17--pl5321h077b44d_0
```

---

## Step 2: Configure `genomepanel_nf` options  

Available parameters

- `-profile`: Optional. `local` skips the SLURM queuing system and runs tasks with up to 4 threads each. `local_highCPU` runs tasks with up to 24 threads each. `slurm` submits all tasks as SLURM jobs. Default: `slurm`.

- `--outdir`: Optional. Folder to save final output files. Default: `./nf_output`.

- `--keep_bam`: If set to `true`, per-sample BAM files will be saved to the output directory. Default: `false`.

- `--keep_gvcf`: If set to `true`, per-sample GVCF files will be saved to the output directory. Default: `false`.

- `-work-dir`: Optional. Defines where to store temporary files (often many TB). Consider `/scratch/work` for large datasets. Default: `./work`. 

- `-resume`: Optional. If set, the pipeline will resume from the last completed step, skipping already completed steps. The `work-dir` needs to be intact for this. This is particularly useful if e.g. the reference genome indexing was already completed in a previous run.

- `--NCBI_API_key`: Required for querying and downloading from NCBI SRA. You can get your key by creating an [account on NCBI](https://account.ncbi.nlm.nih.gov/). After registration/login, find on the top right the link to the "Account settings". Click on "Create API key" and copy it.

- `--reference`: Required. Provide a reference genome fasta file with an absolute path and make sure the file has the `.fasta` extension (not `.fa`, `.fna`or `.fas`).

- `--bwa_index`: Optional. Provide the path prefix to pre-built BWA-mem2 index files. This skips the BWA indexing step, saving time and computational resources with very big genomes. The path should point to the reference prefix (e.g., `/path/to/ref.fasta` if the above option was specified with `--reference /path/to/ref.fasta`). The pipeline will automatically find the associated index files (`.amb`, `.ann`, `.bwt.2bit.64`, `.pac`, `.0123`). 

- `--min_contig_length`: Optional. Filter reference contigs shorter than this value (in base pairs). Useful for excluding small scaffolds or contigs from variant calling. Default: `false` (no filtering).

- `--call_invar_sites`: If set to `true`, GATK HaplotypeCaller will call invariant sites in addition to variant sites. This increases output file size significantly but may be useful for certain downstream analyses. Default: `false`.

- `--reference_segments`: Optional. Size of genome segments (in base pairs) used for parallel processing during variant calling. Smaller values increase parallelization but add overhead. Larger values reduce parallelism but minimize overhead. You can de-activate segmentation by setting the value to `0`. Default: `1000000` (1 Mb).

- `--reads`: Optional. Provide the path to the folder containing the fastq read files. The pipeline will automatically find all paired read files based on the naming convention. Must be bracketed by single quotes `'`. See below for examples. Important: accepts only paired-end reads.

- `--SRA_index`: Optional. Instead of local fastq files, you can provide a file listing NCBI SRA accessions (or ENA, etc.) with one accession per line including `SRR...`, `SRP...`, `SRX...`, `PRNJ...`, etc. If the accession includes multiple `SRR...` runs, all included runs are processed. You can use the [SRA Explorer](https://sra-explorer.info) to collect accession ids. 

  Important:
  - Accepts only paired-end reads locally. Both SE and PE are accepted from SRA.
  - If the download from SRA produces errors (connection reset, etc.), an alternative is to download the files separately, and use the `--reads` option to specify the downloaded files. See below for an example of how to download SRA files manually.

- `--SRR_sample_map`: Optional. A CSV file mapping SRR accession IDs to sample names. This allows multiple SRR accessions to be assigned to the same sample name, which is useful when a sample was sequenced multiple times and should be genotyped as a single combined dataset. The CSV format is: `SRR_ID,Sample_Name` (one mapping per line, no header). If an SRR ID is not listed in the file, the original SRR ID will be used as the sample name. Default: `false` (no mapping). The repository includes an example file `sample_map.csv`.

  Example `sample_map.csv`:
  ```
  SRR1234567,Sample_A
  SRR1234568,Sample_A
  SRR1234569,Sample_B
  SRR1234570,Sample_C
  ```
  In this example, `SRR1234567` and `SRR1234568` will both be assigned to `Sample_A` during genotyping.

- `--ploidy`: Required. Use `1` for haploid genomes, `2` for diploid genomes. Can also be used to define higher ploidy levels in pooled samples.

---

## Step 3: Run `genomepanel_nf` - example options

The below example is based on the _Zymoseptoria tritici_ IPO323 reference genome and Illumina paired-end reads from local file servers and NCBI SRA. Substitute reference genome, NCBI accessions and local read paths with your own data.

### Obtain the reference genome

```bash
# General option - from Ensembl Fungi
wget http://ftp.ensemblgenomes.org/pub/fungi/release-61/fasta/zymoseptoria_tritici/dna/Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
gunzip Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
mv Zymoseptoria_tritici.MG2.dna.toplevel.fa IPO323.fasta

# From local file server (LEGserv)
cp /legserv/NGS_data/Zymoseptoria/Zt_Reference_genomes/19Pangenome_genomes/IPO323/Zymoseptoria_tritici.MG2.dna.toplevel.mt+.fa .
mv Zymoseptoria_tritici.MG2.dna.toplevel.mt+.fa IPO323.fasta
```

### Select local fastq files

The following examples show different ways to select paired-end fastq files. The `--reads` option must be bracketed by single quotes `'`. The examples assume that the read files are named according to the Illumina convention, i.e. ending with `_1.fq.gz` and `_2.fq.gz` or `_R1.fq.gz` and `_R2.fq.gz`. Adjust the patterns according to your own naming conventions.

Note the use of `

```bash
# Option 1 - select all fastq files ending with _1.fq.gz and _2.fq.gz
--reads '/path/to/reads/*{1,2}.fq.gz'

# Option 2 - select all fastq files ending with _1.fq.gz and _2.fq.gz, including all subdirectories (** instead of *)!
--reads '/path/to/reads/**{1,2}.fq.gz'

# Option 3 - select all files ending with _1.fq.gz and _2.fq.gz OR ending with _R1.fq.gz and _R2.fq.gz
--reads '/path/to/reads/*_{,R}{1,2}.fq.gz'

# Option 4 - select all files (including all subdirectories), with optional variation in fq/fastq, 1/R1 (2/R2), optional _001 or _001_ additions
--reads '/path/to/reads/**_{,R}{1,2}{,_001,_001_*}.{fq,fastq}.gz'
````

```bash
# Option 4 will include these files among others:
ST01IR_A48b.cleanData_1.fq.gz and ST01IR_A48b.cleanData_2.fq.gz
ST01IR_A26b.cleanData_R1.fq.gz and ST01IR_A26b.cleanData_R2.fq.gz
ST01IR_A26b.cleanData_R1.fastq.gz and ST01IR_A26b.cleanData_R2.fastq.gz
ST01IR_A26b.cleanData_R1_001.fastq.gz and ST01IR_A26b.cleanData_R2_001.fastq.gz
J9_L2_R1_001_18ku2CAeFgfk.fastq.gz and J9_L2_R2_001_j2kKKZcCX6h0.fastq.gz
```

### Define SRA/ENA accessions

Example file to provide for the `--SRA_index ...` option. 

```bash
ERR13824484
ERR13824571
ERR13824499
```

Save the text file e.g. as `SRA_accessions.txt`. The repository includes an example file.

---

## Step 4: `genomepanel_nf` run example

```bash
# example input reference genome (see above how to obtain it)
REF=$PWD/IPO323.fasta

# read selection example 1 (small test case) - selects 3 paired-end reads from LEGserv
READS='/legserv/NGS_data/Zymoseptoria/Illumina_DNAseq/Croll_2013/ST99CH_{1A,3A,5A}_{1,2}.fq.gz'
# read selection example 2 (medium set) - selects 9 paired-end reads from LEGserv
READS='/legserv/NGS_data/Zymoseptoria/Illumina_DNAseq/Croll_2013/ST99CH_*_{1,2}.fq.gz'
# read selection example 3 (very large set) - selects nearly all available paired-end DNA-seq datasets on LEGserv
READS='/legserv/NGS_data/Zymoseptoria/Illumina_DNAseq/_{,R}{1,2}{,_001,_001_*}.{fq,fastq}.gz'
```


### Pipeline run

Start the pipeline using `slurm` and processing local fastq files and NCBI accessions. Temporary files are written to `/scratch` and the output will be in the `my_nf_run_output` folder. The `SRA_accessions.txt` example file is included in the repository.

```bash
# substitute with your own NCBI API key!
NCBI_API_KEY=abcdef1234567890
# activate conda environment
micromamba activate nf_gp_env
# run nextflow pipeline
export NXF_OPTS='-Xms8g -Xmx64g'
nextflow run main.nf -config nextflow.config -profile slurm \
  -work-dir '/scratch/nf_tmp' --outdir './my_nf_run_output' \
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
```
NCBI_download_urls.tsv
NCBI_SRR_PE_accessions.txt
NCBI_SRR_SE_accessions.txt
```

TSV files summarizing `fastp` and `bwa-mem2` statistics for all samples.
```
fastp_summary.tsv
bwa_summary.tsv
```

Pipeline execution statistics with completion times for all process types.
```
pipeline_execution_stats.txt       # Human-readable formatted report
pipeline_execution_stats.tsv       # Machine-readable tab-separated format
```

The pipeline statistics files include:
- Process name and description (e.g., "BWA Mapping", "GATK HaplotypeCaller")
- Complete task counts for each process type
- Average execution time (wall-clock duration)
- Minimum and maximum execution times
- Useful for identifying bottlenecks, optimizing resources, and documenting pipeline performance

Example output:
```
Process                        Count    Average Time      Range (Min - Max)
---------------------------------------------------------------------------------
SRA Download (PE)              2,415      2m 02s           24s - 9m28s
FASTP Trimming (PE)            2,415         41s            9s - 4m12s
BWA Mapping                    2,415      3m 28s           19s - 16m28s
GATK HaplotypeCaller           2,415     52m 04s          45m12s - 63m28s
```

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
3. `gatk` Haplotypecaller emits GVCF, you need to set `--sample-ploidy` (see above)
4. `gatk` VariantFiltration flags low quality variants based on the following criteria: `QD<20.0`, `MQ<30.0`,`ReadPosRankSum <-2.0 | >2.0`, `MQRankSum <-2.0 | >2.0` and `BaseQRankSum <-2.0 | >2.0`. No filtering based on `QUAL` values as these are sample size dependent.
5. `bcftools` is used to produce a high-quality variants file including only variants passing the GATK VariantFiltration criteria.
6. Variant quality metrics are plotted using an R script.
7. `vcftools` is used to produce a a thinned (1 SNP per kb), MAF > 0.05 and high genotyping rate (> 90 genotyping rate) VCF file.

---

## Features to consider / bug fixes
- include GATK CNV calling
- run basic pop gen analyses (e.g. PCA, admixture)
- include sample renaming step as an option
- allow for multiple SRA accessions or fastq pairs per sample name

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

