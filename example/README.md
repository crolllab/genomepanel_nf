# genomepanel_nf — Example dataset

## Source

All data are from the **E. coli Long-Term Evolution Experiment (LTEE)**,
BioProject [PRJNA295606](https://www.ncbi.nlm.nih.gov/bioproject/PRJNA295606/).

> Tenaillon O, Barrick JE, Ribeck N, Deatherage DE, Blanchard JL, Dasgupta A,
> Wu GC, Wielgoss S, Schneider D, Blount ZD, Lenski RE (2016).
> Tempo and mode of genome evolution in a 50,000-generation experiment.
> *Nature* **536**, 165–170. https://doi.org/10.1038/nature18959

---

## Files

### Reference genome

| File | Accession | Description |
|------|-----------|-------------|
| `ecoli_REL606.fasta` | NC_012967.1 | *E. coli* B str. REL606, complete genome (4.63 Mb). Retrieved via NCBI Entrez (`efetch -db nuccore -id NC_012967.1 -format fasta`). |

### Local FASTQ (pre-downloaded, ~19× coverage each)

Each file was streamed from ENA FTP and truncated to 300,000 read pairs
(150 bp PE) to limit file size. Original full runs are available from ENA/SRA at the accessions below.

| File | SRR accession | Clone | Population | Generation | Full size |
|------|--------------|-------|------------|-----------|-----------|
| `fastq/SRR2589044_{1,2}.fastq.gz` | SRR2589044 | REL2181A | Ara−3 | 5,000 | ~263 MB |
| `fastq/SRR2584863_{1,2}.fastq.gz` | SRR2584863 | REL7179B | Ara−3 | 15,000 | ~374 MB |
| `fastq/SRR2584866_{1,2}.fastq.gz` | SRR2584866 | REL11365 | Ara−3 | 50,000 | ~634 MB |


### Additional SRA accessions (downloaded by the pipeline)

Three accessions are listed in `sra_accessions.txt`. The pipeline resolves each
accession to all associated runs, yielding **six** SRR downloads (two runs per
clone).

| SRR accession | Listed in file | Clone | Population | Generation |
|--------------|:--------------:|-------|------------|------------|
| SRR2591045 | ✓ | REL7180A | Ara−4 | 15,000 |
| SRR2584880 |   | REL7180A | Ara−4 | 15,000 |
| SRR2584867 | ✓ | REL765A  | Ara−4 | 500 |
| SRR2589047 |   | REL765A  | Ara−4 | 500 |
| SRR2591036 | ✓ | REL4532A | Ara+3 | 10,000 |
| SRR2584679 |   | REL4532A | Ara+3 | 10,000 |


### PacBio HiFi run (experimental; not pre-downloaded)

No PacBio HiFi data exist for the LTEE clones, so the HiFi examples use a
**different *E. coli* isolate**: a clinical isolate from BioProject
[PRJEB64289](https://www.ebi.ac.uk/ena/browser/view/PRJEB64289) (*Drivers of
antimicrobial resistance in Uganda and Malawi*). It is listed in
`hifi_accessions.txt`.

| Run accession | Instrument | Reads | Bases | Coverage of REL606 | Download |
|--------------|------------|------:|------:|-------------------:|---------:|
| ERR13744101 | PacBio Sequel IIe (HiFi) | 41,133 | 354 Mb | ~76× | ~217 MB |

Because the isolate is not REL606, expect about 90% of its reads to map and
tens of thousands of variants against the reference. In our test run it had
~36,600 SNPs and ~1,300 indels. The examples show how HiFi input runs, not a
meaningful comparison with the LTEE clones.


## Running the example

Run from the repository root directory. Make sure nextflow is available. The `--SRR_sample_map` option is not required and impacts only sample names (or sample merging) in the VCF output files.

**Option 1 — local FASTQ files only (3 samples):**

```bash
nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads 'example/fastq/SRR*_{1,2}.fastq.gz' \
    --SRR_sample_map example/sample_map.csv \
    --ploidy 1 \
    --outdir example/output
```

**Option 2 — local FASTQ files + 6 SRA downloads (9 read sets for 6 samples total):**

```bash
nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads 'example/fastq/SRR*_{1,2}.fastq.gz' \
    --SRA_index example/sra_accessions.txt \
    --SRR_sample_map example/sample_map.csv \
    --ploidy 1 \
    --outdir example/output
```

**Option 3 — local FASTQ files with the optional PLINK analyses:**

```bash
nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads 'example/fastq/SRR*_{1,2}.fastq.gz' \
    --SRR_sample_map example/sample_map.csv \
    --ploidy 1 \
    --outdir example/output \
    --plink_pca --plink_relationships --plink_ld_prune
```

Results are written to `example/output/9_plink/`. Note that this dataset is haploid and has only
three samples, so it exercises the analyses mechanically rather than producing meaningful
population-genetic results — in particular, the KING matrix is `-inf` because these clonal genomes
carry no heterozygous calls (running the same data with `--ploidy 2` does not change this), and
PCA and LD estimates from three samples are not interpretable.

### PacBio HiFi input (experimental)

HiFi reads are not trimmed. They are mapped with `pbmm2` (`--preset CCS`) and
then called together with the Illumina samples. Each HiFi run gets its own read
group (`PL:PACBIO`) and library, so duplicates are never marked across platforms.

> **Treat indel calls from samples with HiFi data with caution.** HiFi's main
> remaining error is a wrong homopolymer length, and GATK HaplotypeCaller's indel
> error model was built for short reads. It has not been benchmarked on HiFi
> data in this pipeline. SNP calls are less affected.

**Option 4 — local FASTQ files + one HiFi run downloaded from SRA/ENA (4 samples):**

```bash
nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads 'example/fastq/SRR*_{1,2}.fastq.gz' \
    --hifi_SRA_index example/hifi_accessions.txt \
    --SRR_sample_map example/sample_map.csv \
    --ploidy 1 \
    --outdir example/output
```

The resolved HiFi accessions are written to `example/output/1_sra_downloads/hifi/`.

**Option 5 — local FASTQ files + a local HiFi FASTQ file (4 samples):**

Download the same run once (~217 MB), then pass it with `--hifi_reads`:

```bash
mkdir -p example/hifi
wget -O example/hifi/ERR13744101.fastq.gz \
    http://ftp.sra.ebi.ac.uk/vol1/fastq/ERR137/001/ERR13744101/ERR13744101.fastq.gz

nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads 'example/fastq/SRR*_{1,2}.fastq.gz' \
    --hifi_reads 'example/hifi/*.fastq.gz' \
    --SRR_sample_map example/sample_map.csv \
    --ploidy 1 \
    --outdir example/output
```

`--hifi_reads` takes one FASTQ file per run. The file name without its
extension (`ERR13744101`) becomes the run ID. `example/hifi/` is in
`.gitignore`.

Use either Option 4 or Option 5, not both at once: giving the same run as a
local file and as an accession to download is rejected at startup.

In both options the HiFi run is a separate sample, named `ERR13744101` because
`sample_map.csv` has no entry for it. If you have HiFi and Illumina data from
the **same** biological sample, give their runs the same `Sample_Name` in the
sample map, e.g. `ERR13744101,REL7179B`. The runs are then merged before
duplicate marking and called as one sample, and each keeps its own read group
and library.

