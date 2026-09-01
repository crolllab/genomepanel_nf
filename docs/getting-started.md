# Getting started

## Requirements

- **Nextflow** ≥ 23.0
- **Singularity** (or Apptainer) — all pipeline software runs in containers
- A POSIX-compatible file system accessible from all compute nodes (for SLURM execution)
- An [NCBI API key](https://account.ncbi.nlm.nih.gov/) (highly recommended when using `--SRA_index`)

---

## Step 1: Download the latest release

```bash
curl -sL https://github.com/crolllab/genomepanel_nf/archive/refs/tags/latest.tar.gz | tar xz
mv genomepanel_nf-latest genomepanel_nf
cd genomepanel_nf
```

The `latest` tag is automatically updated with every new release.

!!! tip "Alternative"
    You can also browse all releases at [github.com/crolllab/genomepanel_nf/releases](https://github.com/crolllab/genomepanel_nf/releases) and download a specific version.

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

## Step 3: Singularity images

All container images are pulled automatically by Nextflow on the first run. No manual download is required. Images are fetched from [quay.io/biocontainers](https://quay.io/organization/biocontainers) and cached locally so subsequent runs reuse them without re-downloading.

By default the cache is stored in `$HOME/.singularity/cache`. On HPC clusters where `/home` is not shared across worker nodes, point the cache to a shared filesystem in `nextflow.config`:

Example `nextflow.config` snippet if only `/scratch` is shared:

```groovy
singularity {
    cacheDir = "/scratch/$USER/.singularity/cache"
}
```

See [HPC usage & utilities](resources.md#singularity--apptainer) for further Singularity/Apptainer configuration notes.

---

## Step 4: Try the example dataset

The repository ships with a small *E. coli* LTEE dataset that lets you verify your setup end-to-end before working with your own data. The input files live in `example/`.

Run from the repository root:

```bash
nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads 'example/fastq/SRR*_{1,2}.fastq.gz' \
    --ploidy 1 \
    --outdir example/output
```

The run completes in roughly 10–60 minutes on a local machine and produces output in `example/output/`.

---

## Step 5: Prepare your inputs

### Reference genome

The reference genome must be in FASTA format (`.fasta`, `.fa`, `.fna`, or `.fas` extensions are all accepted).

### Local FASTQ files

The `--reads` glob pattern must be bracketed by **single quotes** and must capture paired files.
Without them the shell expands the pattern first and only the first file reaches the pipeline —
see [File paths and glob patterns](configuration.md#file-paths-and-glob-patterns). Common patterns:

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

To read from more than one location, keep everything inside one pair of quotes and separate
the patterns with a **semicolon**:

```bash
--reads '/data/runA/*_{1,2}.fq.gz;/data/runB/*_{1,2}.fq.gz'
```

A comma cannot be used as a separator — it already means alternation inside a glob, as in
`{1,2}`. The same applies to `--bam_input`:

```bash
--bam_input '/data/batch1/*.bam;/data/batch2/*.bam'
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

## Step 6: Run the pipeline

Start the pipeline inside a `tmux` or `screen` session — the Nextflow process must stay alive until completion, even with `-profile slurm`.

```bash
# Run with SLURM, mixed local fastq (e.g. named _1.fq.gz and _2.fq.gz) + SRA input
export NCBI_API_KEY=your_ncbi_api_key_here

nextflow run main.nf -config nextflow.config -profile slurm \
  --NCBI_API_key $NCBI_API_KEY \
  --reference /path/to/reference_genome.fasta \
  --ploidy 2 \
  --reads '/path/to/reads/*{1,2}.fq.gz' \
  --SRA_index './SRA_accessions.txt'
```

To resume a previous run (if the `work-dir` is still intact), simply add `-resume` to the command. Nextflow will skip completed steps and only execute missing ones.

The pipeline validates every parameter before submitting any work. If something is wrong —
a missing file, a glob that matches nothing, a ploidy that was never set — it stops
immediately and lists every problem it found in one block, without having run anything.
Check the `Resolved inputs` section of the startup banner to confirm the pipeline found
the number of read pairs, BAM files or accessions you expected:

```
   Resolved inputs
       Reference      : reference_genome.fasta (412.7 MB)
       Local FASTQ    : 96 files -> 48 read pairs
       SRA accessions : 24 from SRA_accessions.txt
```

Run `nextflow run main.nf --help` at any time for the full parameter list.

!!! warning "Storage"
    The pipeline can require many TB of temporary storage during execution. Point `-work-dir` to a fast scratch filesystem. The pipeline aggressively cleans up temporary files to minimise final storage, but this makes `-resume` less effective after variants have been called.

See the [Configuration](configuration.md) page for a full list of all available parameters.
