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


## Running the example

Run from the repository root directory. Make sure nextflow is available. The `--SRR_sample_map` option is not required and impacts only sample names (or sample merging) in the VCF output files.

**Option 1 — local FASTQ files only (3 samples):**

```bash
nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads "example/fastq/SRR*_{1,2}.fastq.gz" \
    --SRR_sample_map example/sample_map.csv \
    --ploidy 1 \
    --outdir example/output
```

**Option 2 — local FASTQ files + 6 SRA downloads (9 read sets for 6 samples total):**

```bash
nextflow run main.nf \
    --reference example/ecoli_REL606.fasta \
    --reads "example/fastq/SRR*_{1,2}.fastq.gz" \
    --SRA_index example/sra_accessions.txt \
    --SRR_sample_map example/sample_map.csv \
    --ploidy 1 \
    --outdir example/output
```

