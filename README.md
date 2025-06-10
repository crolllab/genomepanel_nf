![alt text](https://github.com/nextflow-io/nextflow/raw/master/docs/_static/nextflow-logo-bg-light.png)

Pipeline to variant call large genome panels
========================================

The `genomepanel_nf` Nextflow pipeline performs reference genome mapping, SNP calling and quality checks. The pipeline accepts either paired-end Illumina fastq files, SRA accessions numbers or both simultaneously. The pipeline can be run locally or through the SLURM queuing system. Analyses are split by chromosome for improved parallelization. 

Implemented steps:
- `sratools`: download SRA files (optional, see below)
- `fastp`: quality control
- `bwa-mem2`: read mapping
- `samtools`: sorting, indexing, and merging
- `picard`: mark duplicates
- `gatk`: HaplotypeCaller and joint genotyping
- `gatk`: VariantFiltration and quality score plotting
- `vctools`: Producing a high-quality variants file
- `plink`: IBS estimation

Current limitations:
- If a sample is represented by multiple SRA accessions or fastq file pairs, the datasets are not combined into a single variant call. 
- The pipeline will use the Illumina read name or NCBI SRA accession numbers for sample/project identification. See below how to make further changes.

## Step 1: Repository, singularity containers and nextflow environment

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

### Get singularity images  
The `singularity` folder must be in the same directory as the `main.nf` file.

A copy of the compatible images is on LEGserv.

```bash
rsync -va /legserv/Temp/Shared/genomepanel_nf/singularity .
```

Alternatively, you can pull the images directly from the Galaxy Project depot.

```bash
mkdir -p singularity
cd singularity
# fastp
singularity pull https://depot.galaxyproject.org/singularity/fastp%3A0.24.1--heae3180_0
# bwa
singularity pull https://depot.galaxyproject.org/singularity/bwa-mem2%3A2.2.1--he70b90d_8
# samtools
singularity pull https://depot.galaxyproject.org/singularity/samtools%3A1.6--h5fe306e_12
# picard
singularity pull https://depot.galaxyproject.org/singularity/picard%3A3.4.0--hdfd78af_0
# gatk
singularity pull https://depot.galaxyproject.org/singularity/gatk4-spark%3A4.6.2.0--hdfd78af_0
# bcftools
singularity pull https://depot.galaxyproject.org/singularity/bcftools%3A1.21--h8b25389_0
# R with tidyverse
singularity pull https://depot.galaxyproject.org/singularity/r-tidyverse%3A1.2.1
# plink2
singularity pull https://depot.galaxyproject.org/singularity/plink2%3A2.00a5.12--h9948957_1
cd ..
```

## Step 2: Configure `genomepanel_nf` options  

Available parameters

- `-profile`: Optional. `local` skips the SLURM queuing system and runs tasks with up to 4 threads each. `local_highCPU` runs tasks with up to 24 threads each. `slurm` submits all tasks as SLURM jobs. Default: `slurm`.

- `--outdir`: Optional. Folder to save final output files. Default: `./nf_output`.

- `-work-dir`: Optional. Defines where to store temporary files (often many TB). Consider `/scratch/work` for large datasets. Default: `./work`. 

- `-resume`: Optional. If set, the pipeline will resume from the last completed step, skipping already completed steps. The `work-dir` needs to be intact for this.

- `--reference`: Required. Provide a reference genome fasta file with an absolute path and make sure the file has the `.fasta` extension (not `.fa` or `.fas`).

- `--reads`: Optional. Provide the path to the folder containing the fastq read files. The pipeline will automatically find all paired read files based on the naming convention. Must be bracketed by single quotes `'`. See below for examples.

- `--SRA_index`: Optional. Instead of local fastq files, you can provide a file listing NCBI SRA accessions (or ENA, etc.) with one accession per line. `SRR...`, `SRP...`, `SRX...`, etc. should work. The header line is mandatory and must include `Accessions`. You can use the [SRA Explorer](https://sra-explorer.info) to collect accession ids.

NB: Some accessions (mostly ENA?) may produce errors (e.g. `ERROR ~ Cannot invoke method split() on null object`). Try to remove these accessions from the list. An alternative is to obtain all ftp download links from the SRA Explorer website and use the `--reads` option to specify the downloaded files.

- `--ploidy`: Required. Use `1` for haploid genomes, `2` for diploid genomes. Can also be used to define higher ploidy levels in pooled samples.

## Step 3: Run `genomepanel_nf` - example options

### Obtain the _Zymoseptoria tritici_ IPO323 reference genome

```bash
# Option 1 - from LEGserv
cp /legserv/NGS_data/Zymoseptoria/Zt_Reference_genomes/19Pangenome_genomes/IPO323/Zymoseptoria_tritici.MG2.dna.toplevel.mt+.fa .
mv Zymoseptoria_tritici.MG2.dna.toplevel.mt+.fa IPO323.fasta

# Option 2 - from Ensembl Fungi
wget http://ftp.ensemblgenomes.org/pub/fungi/release-61/fasta/zymoseptoria_tritici/dna/Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
gunzip Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
mv Zymoseptoria_tritici.MG2.dna.toplevel.fa IPO323.fasta
```

### Select sets of local fastq file pairs

```bash
# Option 1 - select all fastq files ending with _1.fq.gz and _2.fq.gz
--reads '/path/to/reads/*{1,2}.fq.gz'

# Option 2 - select all fastq files ending with _1.fq.gz and _2.fq.gz, including all subdirectories (** instead of *)
--reads '/path/to/reads/**{1,2}.fq.gz'

# Option 3 - select all files ending with _1.fq.gz and _2.fq.gz OR ending with _R1.fq.gz and _R2.fq.gz
--reads './*_{,R}{1,2}.fq.gz'

# Option 4 - select all files (including all subdirectories), with optional variation in fq/fastq, 1/R1 (2/R2), optional _001 or _001_ additions
--reads '/path/to/reads/**_{,R}{1,2}{,_001,_001_*}.{fq,fastq}.gz'

# Option 4 will include these files among others:
ST01IR_A48b.cleanData_1.fq.gz with ST01IR_A48b.cleanData_2.fq.gz
ST01IR_A26b.cleanData_R1.fq.gz with ST01IR_A26b.cleanData_R2.fq.gz
ST01IR_A26b.cleanData_R1.fastq.gz with ST01IR_A26b.cleanData_R2.fastq.gz
ST01IR_A26b.cleanData_R1_001.fastq.gz with ST01IR_A26b.cleanData_R2_001.fastq.gz
J9_L2_R1_001_18ku2CAeFgfk.fastq.gz with J9_L2_R2_001_j2kKKZcCX6h0.fastq.gz
```

### Define NCBI SRA accessions

Example file to provide for the `--SRA_index ...` option. Note the mandatory `Accessions` header.

```bash
Accessions
ERR13824484
ERR13824571
ERR13824499
```
Save the text file e.g. as `SRA_accessions.txt`

## Step 4: `genomepanel_nf` run example

```bash
# example input reference genome (see above)
REF=$PWD/IPO323.fasta

# read selection example 1 (small set) - selects 9 paired-end reads from LEGserv
READS='/legserv/NGS_data/Zymoseptoria/Illumina_DNAseq/Croll_2013/ST99CH_*_{1,2}.fq.gz'
# read selection example 2 (very large set) - selects nearly all available paired-end DNA-seq datasets on LEGserv
READS='/legserv/NGS_data/Zymoseptoria/Illumina_DNAseq/_{,R}{1,2}{,_001,_001_*}.{fq,fastq}.gz'
```

Start the pipeline using `slurm` and processimg local fastq files and NCBI accessions. Temporary files are written to `/scratch` and the output will be in the `genomepanel_nf`. An `SRA_accessions.txt` example file is included in the repository.

```bash
micromamba activate nf_gp_env
nextflow run main.nf -config nextflow.config -profile slurm -work-dir '/scratch/nf_tmp' --outdir './my_nf_run_output' --reference $REF --reads $READS --SRA_index './SRA_accessions.txt' --ploidy 1
```

Notes on the exection:
- Before executing the `nextflow ...` command, enter e.g. a `tmux` session. The session needs to remain active until the end of the pipeline (even if you specify the `slurm` option)
- In `local` and `local_highCPU` modes, the pipeline will run on the server you are logged into. Please be considerate and check how heavy usage is. If you are in doubt, use the `slurm` option to spread the load to all nodes.
  
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

Analysis of variant quality metrics of all identified variants, including plots for `AN` (samples genotyped), `DP` (read depth), `MQ` (mapping quality), `QD` (quality by depth), and `QUAL` (global quality score). The metrics are saved in a compressed CSV file and the plots in PDF format.
```bash
final_variants.metrics.csv.gz
final_variants.plots.AN.pdf
final_variants.plots.DP.pdf
final_variants.plots.MQ.pdf
final_variants.plots.QD.pdf
final_variants.plots.QUAL.pdf
```

PLINK estimation of IBS (identity by state) based on the King method. The output can be used to prune clones.
```bash
final_variants.clean.PLINK.king
final_variants.clean.PLINK.king.id
```

## Description of pipeline steps

1. `fastp` is run with default settings
2. `bwa-mem2` is run with default settings
3. `gatk` Haplotypecaller sets `--sample-ploidy 1`
4. `gatk` VariantFiltration flags low quality variants based on the following criteria: `QD<20.0`, `MQ<30.0`,`ReadPosRankSum <-2.0` or `>2.0`, `MQRankSum <-2.0` or `>2.0` and `BaseQRankSum <-2.0` or `>2.0`. No filtering based on `QUAL` values as these are sample size dependent.
5. `plink2` filters variants for a MAF of 0.1 and estimates King distances.

## Features to consider
- increase retry attempts for NBCI SRA downloads, manage parallel access.
- `vcftools` producing files for population genetics analyses (e.g. MAF filter)
- add GATK CNV calling

## Utilities

### Rename samples in final vcf  

```bash
bcftools reheader --samples id_lookup.txt input.vcf.gz -Oz > output_reheadered.vcf.gz ;

# id_lookup.txt (space-delimited):
oldname1 newname1
oldname2 newname2
oldname3 newname3
oldname4 newname4
```
