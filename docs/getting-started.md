# Getting started

## Requirements

- **Nextflow** ≥ 23.0
- **Singularity** (or Apptainer) — all pipeline software runs in containers
- A POSIX-compatible file system accessible from all compute nodes (for SLURM execution)
- An [NCBI API key](https://account.ncbi.nlm.nih.gov/) (required when using `--SRA_index`)

---

## Step 1: Clone the repository

```bash
git clone git@github.com:crolllab/genomepanel_nf.git
cd genomepanel_nf
```

---

## Step 2: Set up Nextflow

=== "Module (recommended on HPC)"

    ```bash
    module load Nextflow
    ```

    !!! note "Croll lab"
        On LEGcompute you can skip Steps 1–2 entirely by loading the module:
        ```bash
        module load genomepanel_nf
        ```

=== "micromamba / conda"

    ```bash
    micromamba create -n nf_gp_env
    micromamba activate nf_gp_env
    micromamba install -c bioconda nextflow
    ```

---

## Step 3: Pull Singularity images

The `singularity/` folder must be in the same directory as `main.nf`.

```bash
mkdir -p singularity
cd singularity

# entrez-direct (SRA accession resolution)
singularity pull https://depot.galaxyproject.org/singularity/entrez-direct:24.0--he881be0_0

# sra-tools (SRA download)
singularity pull https://depot.galaxyproject.org/singularity/sra-tools%3A3.4.1--h4304569_0

# fastp (trimming & QC)
singularity pull https://depot.galaxyproject.org/singularity/fastp%3A1.3.1--h43da1c4_0

# bwa-mem2 (read mapping)
singularity pull https://depot.galaxyproject.org/singularity/bwa-mem2%3A2.3--he70b90d_0

# samtools (BAM sorting & indexing)
singularity pull https://depot.galaxyproject.org/singularity/samtools%3A1.23.1--ha83d96e_0

# picard (read groups, duplicate removal)
singularity pull https://depot.galaxyproject.org/singularity/picard%3A3.4.0--hdfd78af_0

# gatk4-spark (HaplotypeCaller, GenomicsDBImport, VariantFiltration)
singularity pull https://depot.galaxyproject.org/singularity/gatk4-spark%3A4.6.2.0--hdfd78af_1

# bcftools (VCF filtering)
singularity pull https://depot.galaxyproject.org/singularity/bcftools%3A1.23.1--hb2cee57_0

# R with tidyverse (QC plots)
singularity pull https://depot.galaxyproject.org/singularity/r-tidyverse%3A1.2.1

# vcftools (population-genetics VCF)
singularity pull https://depot.galaxyproject.org/singularity/vcftools%3A0.1.17--pl5321h077b44d_0

cd ..
```

!!! note "Croll lab"
    A copy of all compatible images is available on the file server:
    ```bash
    rsync -va /legserv/Temp/Shared/genomepanel_nf/singularity .
    ```

---

## Step 4: Prepare your inputs

### Reference genome

The reference genome must have the `.fasta` extension (not `.fa`, `.fna`, or `.fas`).

```bash
# Example: Zymoseptoria tritici IPO323 from Ensembl Fungi
wget http://ftp.ensemblgenomes.org/pub/fungi/current/fasta/zymoseptoria_tritici/dna/Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
gunzip Zymoseptoria_tritici.MG2.dna.toplevel.fa.gz
mv Zymoseptoria_tritici.MG2.dna.toplevel.fa IPO323.fasta
```

### Local FASTQ files

The `--reads` glob pattern must be bracketed by single quotes and must capture paired files. Common patterns:

```bash
# All files ending with _1.fq.gz and _2.fq.gz
--reads '/path/to/reads/*{1,2}.fq.gz'

# Including sub-directories
--reads '/path/to/reads/**{1,2}.fq.gz'

# Files ending with _1.fq.gz, _2.fq.gz OR _R1.fq.gz, _R2.fq.gz
--reads '/path/to/reads/*_{,R}{1,2}.fq.gz'

# Flexible pattern covering most Illumina naming conventions
--reads '/path/to/reads/**_{,R}{1,2}{,_001,_001_*}.{fq,fastq}.gz'
```

### SRA/ENA accessions

Create a plain-text file with one accession per line. The pipeline accepts `PRJNA`, `SRP`, `SRX`, `SRR`, and `ERR` accessions:

```bash
PRJNA250875
SRR4235096
ERR13824535
```

The repository includes an example file `SRA_accessions.txt`.

### Sample name mapping (optional)

Use a CSV file to assign custom names and merge multiple SRR runs per sample:

```
SRR1234567,Sample_A
SRR1234568,Sample_A
SRR1234569,Sample_B
SRR1234570,Sample_C
```

Pass it with `--SRR_sample_map sample_map.csv`. The repository includes an example `sample_map.csv`.

---

## Step 5: Run the pipeline

Start the pipeline inside a `tmux` or `screen` session — the Nextflow process must stay alive until completion, even with `--profile slurm`.

```bash
# Set Java heap size for Nextflow
export NXF_OPTS='-Xms8g -Xmx64g'

# Run with SLURM, mixed local + SRA input
nextflow run main.nf -config nextflow.config -profile slurm \
  -work-dir '/scratch/my_nf_tmp' \
  --outdir './my_nf_run_output' \
  --NCBI_API_key $NCBI_API_KEY \
  --reference $PWD/IPO323.fasta \
  --ploidy 1 \
  --reads '/path/to/reads/*{1,2}.fq.gz' \
  --SRA_index './SRA_accessions.txt'
```

To resume a previous run (if the `work-dir` is still intact):

```bash
nextflow run main.nf -config nextflow.config -profile slurm -resume \
  ...
```

!!! warning "Storage"
    The pipeline can require many TB of temporary storage during execution. Point `-work-dir` to a fast scratch filesystem. The pipeline aggressively cleans up temporary files to minimise final storage, but this makes `-resume` less effective after variants have been called.

See the [Configuration](configuration.md) page for a full list of all available parameters.
