# Configuration

All parameters are passed on the command line with `--param value`. Boolean flags are set with `true` or `false`.

Run `nextflow run main.nf --help` for a summary of every parameter.

---

## Startup validation

Every parameter is checked before the pipeline submits a single task, and all problems
are reported together in one block. In particular, each path and glob pattern is resolved
at startup, so a `--reads`, `--bam_input` or `--reference` pattern that matches no files is
a **fatal error** rather than a run that completes without producing any variants.

The startup banner also reports what each input resolved to, which is the quickest way to
confirm the pipeline sees the data you expect:

```
   Resolved inputs
       Reference      : ecoli_REL606.fasta (4.5 MB)
       Local FASTQ    : 6 files -> 3 read pairs
       Sample map     : 9 run IDs -> 6 sample names
```

Non-fatal issues — files with no mate, accession lines that do not look like accessions,
flag combinations with no effect — are reported as `WARN` lines above the banner and do
not stop the run.

---

## File paths and glob patterns

`--reads`, `--hifi_reads` and `--bam_input` take **glob patterns**; `--reference`, `--SRA_index`
and `--hifi_SRA_index` take a single file. The rules below apply to all of them.

### Quoting

**Always use single quotes around a glob pattern.**

| Form | Works? | What happens |
|------|--------|--------------|
| `--reads 'data/*_{1,2}.fastq.gz'` | ✅ **Use this** | The pattern reaches Nextflow intact and Nextflow expands it. |
| `--reads "data/*_{1,2}.fastq.gz"` | ⚠️ Usually | The shell does not glob-expand inside double quotes, so this normally behaves identically — but `$` and `` ` `` are still interpreted, so a path containing them breaks. |
| `--reads data/*_{1,2}.fastq.gz` | ❌ **Silently wrong** | The **shell** expands the pattern first. `--reads` receives only the *first* file and Nextflow discards the rest. |

The unquoted form is the dangerous one, because nothing about it looks wrong:

```bash
# The shell turns this ...
--reads data/*_{1,2}.fastq.gz
# ... into this, and only the first path is kept:
--reads data/A_1.fastq.gz data/B_1.fastq.gz data/A_2.fastq.gz data/B_2.fastq.gz
```

The pipeline detects this: any argument left unattached to a parameter is reported as an
error naming the parameter that swallowed it, together with the files that were dropped.
A quoted pattern is never at risk, so single-quoting is the habit worth keeping.

No quoting is needed for a plain path with no wildcard in it, such as
`--reference /data/genome.fasta`, though quoting does no harm.

### Reading from several locations

Give **one quoted value** and separate the patterns with a **semicolon**:

```bash
--reads 'runA/*_{1,2}.fastq.gz;runB/*_{1,2}.fastq.gz'
--bam_input 'batch1/*.bam;batch2/*.bam'
```

Files matched by all the patterns are pooled into a single set of samples, and duplicates
matched by more than one pattern are counted once. The startup banner reports the total, so
you can confirm every location was picked up.

!!! warning "A comma is not a separator"
    A comma already means alternation *inside* a glob — the `{1,2}` in `*_{1,2}.fastq.gz` —
    so it cannot also separate patterns. `path1,path2`, `path1|path2` and `path1 path2` are
    each rejected at startup with a message pointing at the semicolon form.

`--reference`, `--SRA_index` and `--hifi_SRA_index` accept exactly one file each; a pattern matching several
files is rejected.

---

## Execution mode

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-profile` | `string` | `local` | Execution profile. `local` — up to 4 threads per task. `local_highCPU` — up to 24 threads. `slurm` — submit all tasks as SLURM jobs (requires `--slurm_queue`). |
| `-resume` | flag | — | Resume from the last completed step. Requires the `work-dir` to be intact. |
| `-work-dir` | `path` | `./work` | Directory for temporary and intermediate files. Use a fast scratch filesystem for large datasets. Note the single dash — `--workdir` is not a pipeline parameter and the pipeline will tell you so. |
| `--help` | flag | — | Print all parameters with their defaults and exit. |
| `--outdir` | `path` | `./nf_output` | Directory for final output files. |
| `--slurm_queue` | `string` | — | **Required with `-profile slurm`.** Name of the SLURM partition to submit all jobs to. The partition should allow a maximum walltime of at least 7 days for large datasets. Shorter limits (1–2 days) may work for smaller genomes or low-depth sequencing, but any job exceeding the partition's walltime limit will fail. |

---

## Read input options

Provide either or both of `--reads` and `--SRA_index`, optionally together with PacBio HiFi reads (`--hifi_reads`, `--hifi_SRA_index`; experimental). Alternatively, provide `--bam_input` if you have pre-processed BAM files (can't be combined with any read input). See below for details.

### Local FASTQ files

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--reads` | `glob` | — | Glob pattern pointing to paired-end FASTQ files. Accepts paired-end reads only. Single-quote the pattern; separate several locations with `;`. See [File paths and glob patterns](#file-paths-and-glob-patterns). |

### SRA / ENA accessions

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--SRA_index` | `path` | — | Path to a plain-text file listing NCBI/ENA single or paired-end Illumina read accessions (one per line). Accepts `SRR`, `SRX`, `SRP`, `PRJNA`, `ERR`, etc. |
| `--NCBI_API_key` | `string` | — | **Highly recommended with `--SRA_index`.** Passed to E-utilities as `NCBI_API_KEY`, raising the metadata lookup rate limit from 3 to 10 requests/second. Get your personal [NCBI API key](https://account.ncbi.nlm.nih.gov/). |
| `--SRR_sample_map` | `path` | `false` | CSV file mapping run IDs to sample names, optionally with a library ID (`Run_ID,Sample_Name[,Library_ID]`, no header). Must be comma-separated — a tab-separated file is rejected at startup, because sample names are looked up by comma and every lookup would silently miss. A leading UTF-8 byte-order mark (common in CSVs saved from Excel) is stripped automatically, so it cannot silently break the first line's lookup. See [Getting started](getting-started.md) for format. |

!!! info "Several runs, one sample"
    When more than one run maps to the same `Sample_Name`, the pipeline merges their
    BAMs and marks duplicates across the combined reads — GATK's best practice, since
    duplicate fragments from the same sample can only be recognised once every read is
    in one BAM. Each merged sample still produces exactly **one** BAM and **one** gVCF,
    which is what lets `GenomicsDBImport` accept it: a sample name that shows up on more
    than one gVCF at the same interval is a fatal `GenomicsDBImport` error, not something
    it merges for you.

    `Library_ID` is optional. Without it, each run is treated as its own library —
    assuming several runs share a library, with no other evidence, is not a safe
    default, since duplicate marking is scoped to the library.

### PacBio HiFi reads (experimental)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--hifi_reads` | `glob` | — | Glob pattern pointing to PacBio HiFi FASTQ files (`.fastq`, `.fq`, optionally gzipped), **one file per run**. The run ID is the file name without its FASTQ extension and must be unique. It must not match any `--reads` run or any accession listed for download, since the same run would otherwise be merged into its sample twice. Single-quote the pattern; separate several locations with `;`. |
| `--hifi_SRA_index` | `path` | — | Plain-text file listing PacBio HiFi SRA/ENA accessions, one per line — in the same format as `--SRA_index`, but a separate file. An accession may not be listed in both. Paired-end runs resolved from it are skipped with a warning, since they cannot be PacBio data. |

HiFi runs can be given on their own or together with Illumina input. They are not trimmed
(HiFi reads are consensus-called and adapter-free) and are mapped with
[pbmm2](https://github.com/PacificBiosciences/pbmm2), PacBio's minimap2 wrapper, using
`--preset CCS` against a reference index built once per run. pbmm2 writes the read group
itself:

```
@RG  ID:<run_id>  SM:<sample_name>  LB:<sample_name>_<run_id>_HIFI_LB  PL:PACBIO
```

From there a HiFi BAM follows the same path as an Illumina one: runs of the same sample
are merged, duplicates are marked, and the sample is called with GATK HaplotypeCaller and
joint-genotyped with the rest of the panel.

!!! info "Combining HiFi and Illumina reads of one sample"
    Give the HiFi run and the Illumina runs the same `Sample_Name` in `--SRR_sample_map`:

    ```
    SRR2584863,REL7179B
    hifi_REL7179B,REL7179B
    ```

    Their BAMs are merged into one and called as a single sample, since GATK groups reads by
    the `SM` tag. Each run keeps its own read group `ID` and library `LB`. Duplicate
    marking is scoped to the library, so HiFi reads are never compared with Illumina reads.
    If you set `Library_ID` in the map yourself, never give a HiFi run the same library
    as an Illumina run.

!!! warning "Experimental"
    - **Treat indel calls in samples with HiFi data with caution.** HiFi's main remaining
      error is a wrong homopolymer length, and HaplotypeCaller's indel error model (its
      default `--pcr-indel-model CONSERVATIVE`, which the pipeline does not change) was
      built for short reads. Indel calling has not been benchmarked on HiFi data in this
      pipeline; a long-read caller such as DeepVariant is generally more accurate for
      HiFi indels. SNP calls are less affected. The same caution is printed at startup
      whenever HiFi input is given.
    - Only HiFi (CCS) reads are supported. Older PacBio subread or CLR data in the SRA
      downloads without error but maps poorly under the CCS preset. Check that each
      accession is a HiFi run.
    - Unaligned PacBio BAM (`hifi_reads.bam`) is not accepted by `--hifi_reads`. Convert
      it first with `samtools fastq hifi_reads.bam | gzip > run.fastq.gz`.
    - HiFi runs appear in `4_bwa_mapping/` as `<run>_HiFi` columns, but not in the fastp
      tables, since they are not trimmed.

### Pre-processed BAM files

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--bam_input` | `glob` | — | Glob pattern for pre-existing BAM files. Skips trimming and mapping and starts directly with variant calling. Cannot be combined with `--reads`, `--SRA_index`, `--hifi_reads` or `--hifi_SRA_index`. Single-quote the pattern; separate several locations with `;`. See [File paths and glob patterns](#file-paths-and-glob-patterns). |

!!! warning "BAM file requirements"
    BAM files provided via `--bam_input` must be:

    - Coordinate-sorted
    - Containing `@RG` read group information in the header, including an `SM` (sample) tag
    - Accompanied by a `.bai` index file in the same directory (either `sample.bam.bai` or `sample.bai`)

    The **index is checked at startup** and every BAM missing one is listed in a single error.
    Coordinate sorting and the presence of `@RG` headers are *not* validated — ensure your
    files comply before running.

!!! info "Sample identity comes from the BAM header, not the filename"
    Several `--bam_input` files sharing one `@RG SM` tag are treated as one sample: merged
    and put back through duplicate marking, the same as several runs mapped to one
    `Sample_Name` under `--reads`/`--SRA_index` (see above) — including the pipeline's own
    `--keep_bam` output, where a file is *named* by run but *tagged* by sample. A sample
    backed by a single BAM is passed through unchanged, since `--bam_input` already expects
    pre-processed, deduplicated BAMs and there is nothing to redo.

---

## Reference genome options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--reference` | `path` | — | **Required.** Absolute path to the reference genome in FASTA format, uncompressed. Accepts `.fasta`, `.fa`, `.fna`, and `.fas` extensions. Exactly one file — not a pattern. |
| `--reference_segments` | `integer` | `0` | Size in bp of genome segments used for parallel variant calling. `0` calls one task per contig. Smaller values increase parallelism at the cost of per-task overhead. See the note below. |
| `--min_contig_length` | `integer` | `false` | Filter reference contigs shorter than this value (bp). Useful for excluding small scaffolds. `false` disables filtering. |
| `--bwa_index` | `path` | — | Path to a pre-built BWA-mem2 index, given as **the FASTA path the index was built from** — normally the exact same value as `--reference`. Skips BWA indexing. See the warning below. |

!!! tip "When to set `--reference_segments`"
    With the default `0`, variant calling is scattered one task per contig, so task
    duration follows contig length. A genome with a few large chromosomes and many small
    scaffolds produces a very uneven mix: most tasks finish in seconds while a handful run
    for hours, and the stage cannot finish before its longest task. Adding cores or raising
    `maxForks` does not shorten that tail.

    Segmenting (for example `--reference_segments 1000000` for 1 Mb windows) splits the
    large contigs into comparable pieces and is usually the larger wall-clock win on such
    assemblies. It costs one scheduling and container startup per extra task, and adds a
    `MergeGVCFs` step when `--keep_gvcf` is set. Chromosome-scale assemblies with contigs
    of similar size gain little from it.

!!! warning "`--bwa_index` takes the FASTA path, not an index file"
    `bwa-mem2 index ref.fasta` writes its five files by appending suffixes to the
    FASTA name: `ref.fasta.amb`, `ref.fasta.ann`, `ref.fasta.bwt.2bit.64`,
    `ref.fasta.pac`, `ref.fasta.0123`.

    The pipeline rebuilds those names the same way — by appending each suffix to
    whatever you pass. So the value must be the **FASTA path itself**:

    ```bash
    # correct - same value as --reference
    --reference reference/genome.fasta \
    --bwa_index reference/genome.fasta
    ```

    Pointing at one of the index files instead is the common mistake, and it
    fails in a way that is hard to read:

    ```bash
    # WRONG - do not point at an index file
    --bwa_index reference/genome.fasta.bwt.2bit.64
    ```

    That makes the pipeline look for `genome.fasta.bwt.2bit.64.amb`,
    `genome.fasta.bwt.2bit.64.bwt.2bit.64` and so on. None exist, so Nextflow
    stages broken symlinks and **every mapping task fails** with:

    ```
    ERROR! Unable to open the file: <reference>.bwt.2bit.64
    ```

    If you see that message, check `--bwa_index` first. The index files must all
    sit in the same directory as the FASTA.

    Omit `--bwa_index` entirely to have the pipeline build the index itself.

---

## Genotyping options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--ploidy` | `integer` | — | **Required.** Ploidy level for GATK HaplotypeCaller. `1` for haploid (fungi, bacteria), `2` for diploid. Higher values can represent pooled samples. |
| `--call_invar_sites` | `boolean` | `false` | When `true`, GATK HaplotypeCaller also emits invariant (monomorphic) sites. Substantially increases output size. Useful for some downstream analyses requiring full genome coverage. |

---

## Population-genetics analyses

Optional PLINK analyses run at the very end of the pipeline, on the population-genetics VCF
(thinned, MAF- and missingness-filtered). Each is off by default and enabled with its own flag.
All results are written to `<outdir>/9_plink/`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--plink_pca` | `boolean` | `false` | Principal component analysis (PLINK 2, `--pca`). Up to 10 PCs, automatically capped at *n* samples − 1. |
| `--plink_relationships` | `boolean` | `false` | Pairwise relatedness between all samples. Runs **both** `--make-rel` (GRM) and `--make-king` (KING kinship) in PLINK 2, as the two answer different questions — see below. |
| `--plink_ld_prune` | `boolean` | `false` | Linkage-disequilibrium pruning (PLINK 2, `--indep-pairwise 50 5 0.5`), plus the pruned VCF. |

### Choosing between the two relationship matrices

`--plink_relationships` produces two square matrices over the same samples and variants. They are
not interchangeable:

| | `--make-rel` → `.rel` | `--make-king` → `.king` |
|---|---|---|
| **Estimates** | Genomic relationship matrix (GRM): an allele-sharing correlation matrix between individuals, based on identity by state | KING kinship coefficients: an identity-by-descent estimate of the co-segregation of alleles from shared ancestors |
| **Scale** | Correlation-like. Self-relatedness ≈ 1; a parent–child pair ≈ 0.5 | Kinship. Self-kinship = 0.5; a parent–child pair ≈ 0.25; unrelated ≈ 0 |
| **Needs allele frequencies** | Yes — supplied by the pipeline via `--read-freq` | No — derived internally |
| **Population structure** | Sensitive. The zero-mean and variance normalisation is computed across the whole sample, so strong structure dominates the estimates and distorts familial relationships | Robust. Preferred when population structure is present or unaccounted for |
| **Use it for** | Mixed models, heritability, kinship-aware association testing — anything expecting a GRM | Identifying relatives and filtering duplicates or close kin before analysis |

Following the [PLINK 2 relatedness tutorial](https://www.cog-genomics.org/plink/2.0/tutorials/qc2b),
prefer the KING matrix for relationship filtering whenever population structure may be unaccounted
for. The pipeline writes complete symmetric matrices (`square`) rather than the tutorial's
half-filled `square0`, so they load directly into R or Python without symmetrising.

Both matrices are computed from the population-genetics VCF, which vcftools has already filtered to
MAF ≥ 0.05. Relatedness estimation needs reasonably common variants — empirical minor allele
frequencies are reliable down to roughly *n*<sup>−0.5</sup> — so no further MAF filter is applied.

!!! warning "KING requires heterozygous genotypes"
    The KING estimator divides by the heterozygous site count of the *less heterozygous* member of
    each pair. Any pair in which one sample has no heterozygous calls therefore comes out as `-inf`,
    and the `.king` matrix carries no information for that pair.

    This affects haploid (`--ploidy 1`) data — where heterozygotes cannot exist — but also fully
    homozygous diploid panels such as inbred lines, selfing species and clonal isolates. **Raising
    `--ploidy` does not fix it:** calling a haploid organism as diploid yields `0/0` and `1/1`
    genotypes with essentially no heterozygotes, and the matrix stays `-inf`.

    The `.rel` (GRM) matrix remains well defined in all of these cases and is the one to use. The
    pipeline emits a warning at startup when `--ploidy 1` is combined with this analysis; the
    homozygous-diploid cases cannot be detected up front, so check the `.king` matrix for `-inf`
    before relying on it.

!!! note "Small panels"
    PLINK 2 declines to estimate allele frequencies and LD from fewer than 50 samples. The pipeline
    works around this by supplying allele frequencies computed from the panel itself (`--read-freq`)
    for PCA, and by passing `--bad-ld` for LD pruning. Both analyses therefore complete on small
    panels, but the resulting estimates should be treated with caution.

---

## Copy-number variant calling

`--cnv` adds germline copy-number variant (CNV) calling with GATK's
[gCNV](https://gatk.broadinstitute.org/hc/en-us/articles/360035531152) workflow in **cohort
mode**: the panel itself is the cohort, from which gCNV learns the coverage biases shared by all
samples, so no panel of normals is needed. It calls integer copy numbers per sample — per bin,
as segments, and, with a gene annotation, per gene. Results are written to `<outdir>/11_cnv/`
(see [Output](output.md#11_cnv)).

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--cnv` | `boolean` | `false` | Turn on CNV calling. |
| `--cnv_bin_length` | `integer` | `1000` | Length in bp of the bins in which reads are counted — the resolution of the calls. See [Choosing the bin length](#choosing-the-bin-length). |
| `--cnv_gene_annotation` | `path` | — | GTF or GFF3 file (optionally gzipped). Adds per-gene copy numbers. Its contig names must match the reference; genes on contigs the reference lacks (including those removed by `--min_contig_length`) get no calls. |
| `--cnv_gene_feature` | `string` | `gene` | Feature type (column 3 of the annotation) that defines a gene. With the default, gene subtypes count too (`protein_coding_gene`, `ncRNA_gene`, `pseudogene`), and genes without a gene line are rebuilt from their transcripts or exons/CDS (see below). Any other value uses only features of exactly that type. |
| `--cnv_contig_ploidy_priors` | `path` | — | Per-contig ploidy priors for GATK `DetermineGermlineContigPloidy`. Default: for every contig, 0.97 on `--ploidy` and the remaining 0.03 spread over ploidy 0 to `--ploidy` + 1. Give your own for sex chromosomes, or to make ploidy 0 more likely for accessory chromosomes. Format below. |
| `--cnv_exclude_intervals` | `path` | — | Regions to leave out: a BED file, a Picard `.interval_list`, or a GATK `.intervals`/`.list` file with one `contig` or `contig:start-end` per line. Exclude the mitochondrial genome and other organelles — their coverage is hundreds of times that of the nuclear genome — and, if known, rDNA arrays and large repeat clusters. |
| `--cnv_max_copy_number` | `integer` | `5` | Highest copy number gCNV can call; higher copy numbers are reported as this value. Raise it for tandemly expanded gene families. Runtime and memory grow with it. Must be at least `--ploidy` + 1. |
| `--cnv_min_qs` | `integer` | `50` | Segments, and genes, whose quality (QS, Phred-scaled) is below this are flagged `LowQual`. Calls are flagged, not removed. |
| `--cnv_min_mapq` | `integer` | `30` | Reads below this mapping quality are not counted. Multi-mapping reads in repeats have mapping quality 0, so repeats show as low coverage; gCNV models that as a bin-specific bias shared by the cohort. |
| `--cnv_shard_bins` | `integer` | `10000` | Bins per `GermlineCNVCaller` task. Memory of each task grows with bins × samples; lower it if those tasks run out of memory on large panels. |
| `--cnv_bin_matrix` | `boolean` | `false` | Also write `cnv_bins.tsv.gz`, the bin × sample copy-number matrix. Off by default because it is large for big genomes (3 Gb at 1 kb bins is 3 million rows). |
| `--cnv_gc_correction` | `boolean` | `false` | Let gCNV correct each sample's GC bias. Off by default: with the pipeline's model settings it misreads normal coverage in AT-rich regions as high copy numbers (see [Model settings](#model-settings)). Turn it on for libraries with strong GC bias, e.g. heavily PCR-amplified ones, and check that normal regions stay at the reference copy number. Bins below 10% or above 90% GC are removed either way. |

Duplicate-flagged reads are counted only with `--use_duplicate_reads`, as for variant calling.

### Gene annotation formats

GFF3 and GTF are recognised from their attribute syntax, so the file extension does not
matter, and gzipped files, Windows line endings, a UTF-8 byte-order mark, UCSC
`track`/`browser` lines and an embedded `##FASTA` section are all accepted. GTF values
may be quoted (`gene_id "g1";`) or not (`gene_id g1;`); GFF3 values are URL-decoded.

With `--cnv_gene_feature gene` (the default), every gene, transcript (`mRNA`,
`transcript`), exon and CDS line is grouped under the gene it belongs to, so it does not
matter which of these levels a file contains:

- **GFF3**: `Parent` links are followed up to the top-level feature. Files written by
  gffread, whose transcripts have no `Parent`, are grouped by their `geneID` attribute.
- **GTF**: lines are grouped by `gene_id`.

Each gene spans the outermost of its features, so a gene written over several lines
under one `ID`, or several isoforms of one gene, gives one gene. The gene ID in the output
tables is the GFF3 `ID` of the gene (or of the top-level feature), or the GTF `gene_id`;
the gene name is its `Name` / `gene_name`, or the ID when there is none. The log of
`CNVSummary` reports how many genes came from gene lines and how many were rebuilt.

This was tested on variants of one fungal annotation: NCBI and Ensembl-style GFF3,
NCBI GTF, GTFs with only transcripts or only exons/CDS, gffread output with and without
isoforms, files with gene lines for only some loci, and the formatting variants above.
Every variant describing the same genes gave the same genes and the same copy-number
calls. An annotation whose contig names do not match the reference is rejected at
startup.

### Choosing the bin length

The bin length trades resolution against noise. gCNV counts read starts, so a bin holds about
*depth* × *bin length* / *read length* reads, and its count fluctuates by roughly one over the
square root of that. Aim for at least ~100 reads per bin at the panel's typical depth:

| Depth (150 bp reads) | Bin length for ~100 reads per bin |
|---|---|
| 5× | 3000 bp |
| 10× | 1500 bp |
| 30× | 500 bp |

Two further constraints:

- **Gene-level calls** need bins clearly shorter than the genes of interest. A gene shorter than
  a bin still gets a call, from the bin(s) it overlaps, but that call mostly reflects its
  neighbourhood. The `n_bins` column of the gene tables shows how many bins each gene spans.
- **Compute** grows with the number of bins × samples. A 40 Mb genome at 1 kb bins has 40,000
  bins, which is quick; a 3 Gb genome has 3 million, which needs many `GermlineCNVCaller` shards.

### Model settings

gCNV's own defaults were made for exome and human data, and they miss deletions that many
samples share: the model lets each bin's unexplained variance grow until a shared deletion
looks like noise, and its "bias factors" learn the deletion as a coverage bias of the bin.
On a panel of 434 isolates of a haploid fungus, they called none of the 247 isolates that lack
a 2 kb mating-type gene as deleted, and found only about 10% of the deletions carried by half
the panel or more. The pipeline therefore runs `GermlineCNVCaller` with the settings of the
GATK-SV whole-genome pipeline, adjusted on that panel:

| GATK option | Pipeline | GATK default |
|---|---|---|
| `--interval-psi-scale`, `--sample-psi-scale` | `1e-4` | `0.01` |
| `--p-active` | `0.01` | `0.1` |
| `--p-alt` | `1e-6` | `5e-4` |
| `--enable-bias-factors` | `false` | `true` |
| `--log-mean-bias-standard-deviation` | `0.01` | `0.1` |
| `--class-coherence-length`, `--cnv-coherence-length` | `--cnv_bin_length` | `10000` |
| `--copy-number-posterior-expectation-mode` | `EXACT` | `HYBRID` |
| `--caller-update-convergence-threshold` | `1e-6` | `0.001` |
| `--learning-rate` | `0.03` | `0.01` |
| `--convergence-snr-trigger-threshold` | `0.2` | `0.1` |
| `--convergence-snr-averaging-window` | `100` | `500` |
| GC-bias model (`--annotated-intervals`) | off (`--cnv_gc_correction`) | on |

`FilterIntervals` also runs with `--low-count-filter-percentage-of-samples 90` instead of GATK's
50, so a bin is dropped only when more than 90% of samples have fewer than 10 reads in it.
GATK's default would drop every deletion carried by most of the panel before calling.

On a 2 Mb test region of that panel, scored against the raw read counts, these settings
called the mating-type gene deleted in all 247 isolates lacking it and in none of the 182
carrying it. They found 74%, 86% and 95% of deleted bins carried by under 10%, 10–50% and
50% or more of the isolates, against 57%, 13% and 10% with GATK's defaults. No bin with normal
coverage was called deleted. Called gains matched the coverage: bins called CN2 to CN5 had
1.8, 2.7, 3.6 and 5.9 times normal coverage. Normal-coverage bins called at another copy number
fell from 1.5% to 0.2%. The results held for subsets of 30 and 10 isolates.

Genome-wide on the same 434 isolates (43,500 bins of 1 kb), compared with GATK's defaults:
- **Deletions found**, by how many isolates carry them: under 10%, 80% (was 52%); 10–50%, 83% (was 17%); 50–90%, 94% (was 6%).
- **False calls:** no normal-coverage bin was called deleted, and 0.2% got another copy number (was 0.5%).
- **Deleted sequence per isolate:** a median of 1.37 Mb, close to the 1.4 Mb of near-zero coverage in the raw counts.
- **Cost:** about the same as with GATK's defaults: each 10,000-bin `GermlineCNVCaller` shard took about 5 hours on 4 CPUs and peaked at 4.8 GB.

Two of the settings matter most, and are best not changed alone. With the variance held
lower still (`1e-6`, the GATK-SV value), the model can no longer absorb ordinary noise; it
explains it with CNVs instead, and normal coverage is called CN4–5. With the GC-bias model on,
each sample's GC curve becomes the one flexible term left; in AT-rich regions it drifted
about five-fold and turned normal coverage into CN5 calls in 13% of normal bins.
`--cnv_gc_correction` switches it back on for data that need it.

The settings were tuned on one haploid organism. They come from the GATK-SV pipeline for human
(diploid) genomes, which holds the variance even lower. Check `cnv_sample_summary.tsv` for
samples with unusually many calls, and see the next section to change any of them.

### Contig-ploidy priors format

A tab-separated table with a row for every contig of the reference (after `--min_contig_length`)
and one column per ploidy state, each row summing to 1:

```
CONTIG_NAME	PLOIDY_PRIOR_0	PLOIDY_PRIOR_1	PLOIDY_PRIOR_2	PLOIDY_PRIOR_3
chr1	0.01	0.01	0.97	0.01
chrX	0.01	0.49	0.49	0.01
```

The called ploidy of every contig in every sample is in `11_cnv/cnv_contig_ploidy.tsv`, which
directly shows aneuploidy and the presence or absence of accessory chromosomes.

!!! warning "What gets called, and what doesn't"
    - **Short-read samples only.** Samples with any PacBio HiFi data (or, with `--bam_input`, any
      `PL:PACBIO` or `PL:ONT` read group) are left out with a warning: gCNV counts read starts
      per bin, and one 15 kb HiFi read counts once, so long-read coverage cannot share a cohort
      model with short-read coverage. This includes samples that also have Illumina runs.
    - **Cohort size.** gCNV learns what normal coverage looks like from the cohort. It is most
      reliable with 30 or more samples, and the pipeline warns below that; with fewer than 2 it
      does not call CNVs at all. The cohort should be technically homogeneous — a panel mixing
      very different library preparations or read lengths gives noisier calls.
    - **Fragmented assemblies.** gCNV fits a ploidy per contig, so thousands of small scaffolds
      make it slow and its ploidy calls unstable. Use `--min_contig_length` (e.g. `50000`).
    - **Shared CNVs.** Before calling, GATK `FilterIntervals` removes bins with fewer than 10 reads
      in more than 90% of samples, bins among the lowest or highest 1% of counts in more
      than 90% of samples, and bins below 10% or above 90% GC. A deletion carried by nearly the
      whole panel (more than 90%) is therefore not called: there is too little normal coverage left
      to call it against.

!!! tip "Passing other GATK options"
    Any further GATK argument can be added per step with `ext.args` in a custom config
    (`-c my.config`). An option given there replaces the pipeline's own value for it (see
    [Model settings](#model-settings)). For example, to relax the GC filter, or to go back to
    GATK's own `GermlineCNVCaller` defaults:

    ```groovy
    process {
        withName:CNVFilterIntervals { ext.args = '--minimum-gc-content 0.05 --maximum-gc-content 0.95' }
        withName:CNVGermlineCaller  {
            ext.args = '--interval-psi-scale 0.01 --sample-psi-scale 0.01 --p-active 0.1 --p-alt 5e-4 ' +
                       '--enable-bias-factors true --log-mean-bias-standard-deviation 0.1 ' +
                       '--class-coherence-length 10000 --cnv-coherence-length 10000 ' +
                       '--copy-number-posterior-expectation-mode HYBRID --caller-update-convergence-threshold 0.001 ' +
                       '--learning-rate 0.01 --convergence-snr-trigger-threshold 0.1 --convergence-snr-averaging-window 500'
        }
    }
    ```

    together with `--cnv_gc_correction`. `ext.args` is read by `CNVFilterIntervals`,
    `CNVContigPloidy` and `CNVGermlineCaller`.

---

## Output options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--keep_bam` | `boolean` | `false` | When `true`, saves final per-sample BAM files (after duplicate marking) to `<outdir>/5_bam_files/`. |
| `--keep_gvcf` | `boolean` | `false` | When `true`, saves per-sample GVCF files to `<outdir>/6_gvcf_files/`. |

---

## Advanced options

Minor, rarely-needed settings for special use cases.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--use_duplicate_reads` | `boolean` | `false` | When `true`, disables GATK HaplotypeCaller's `NotDuplicateReadFilter`, so reads flagged as duplicates by the `dupRemoval` process are still used for variant calling. By default, duplicate-flagged reads are excluded from calling. |
| `--genomicsdb_batch_size` | `integer` | `200` | Number of samples GATK `GenomicsDBImport` loads per batch (`--batch-size`). The default is high enough that a typical panel imports in a single pass, which is the fastest option. Lower it to reduce peak memory on very large panels — smaller batches hold fewer samples open at once, at the cost of extra passes over the interval. |

---

## SLURM and concurrency

These settings are found in `nextflow.config` and can be edited directly.

| Setting | Default | Description |
|---------|---------|-------------|
| `executor.queueSize` | 500 | Maximum tasks in flight (submitted but not yet complete) across all processes. |
| `executor.submitRateLimit` | `'500/1min'` | Maximum task submission rate (prevents overwhelming the scheduler). |
| SRA download `maxForks` | 10 | Maximum concurrent SRA downloads (PE and SE each). Reduce if NCBI rate-limits your connection. |
| fastp `maxForks` | 20 | Maximum concurrent trimming tasks (PE and SE each; I/O intensive). |
| GATK HC `maxForks` | 500 | Maximum HaplotypeCaller tasks in flight. Capped in turn by `executor.queueSize`, so raise both together. |

These limits count tasks that are **submitted but not yet complete**, not tasks that
are running, and they are deliberately set above the concurrency a cluster typically
grants so that the surplus waits in the SLURM queue and backfills a freed core without
a round trip through Nextflow. See
[Concurrency and rate limits](resources.md#concurrency-and-rate-limits) for how to size
them for your cluster.

!!! note "SLURM partition walltime requirements"
    Several pipeline processes request up to **7 days** of walltime (e.g. BWA mapping, GATK HaplotypeCaller, GenomicsDB import). When using `-profile slurm`, all jobs are submitted to the partition specified with `--slurm_queue`. This partition must allow a maximum walltime sufficient for the longest-running jobs.

    **Recommended:** use a partition with a 7-day (or unlimited) walltime limit.

    **Shorter partitions (1–2 days)** may still work if:

    - Your reference genome is small (e.g. bacteria, fungi)
    - Sequencing depth is low
    - The number of samples is modest

    If a job exceeds the partition's walltime limit, SLURM will kill it and the pipeline will fail at that step. Use `-resume` to restart from the last completed task after switching to a longer partition.

    To list available partitions and their maximum walltimes on your cluster:
    ```bash
    scontrol show partition | grep -E "PartitionName|MaxTime"
    ```
    This prints each partition name alongside its `MaxTime` limit. A value of `UNLIMITED` means no walltime cap.

    Example usage:
    ```bash
    nextflow run main.nf -profile slurm --slurm_queue long [other params]
    ```

