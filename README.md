![alt text](https://github.com/crolllab/genomepanel_nf/blob/main/logo.png?raw=true)

Pipeline to variant call large genome panels
========================================

**genomepanel_nf** is a [Nextflow](https://www.nextflow.io/) pipeline for highly efficient reference genome mapping, variant (SNP/indel) calling and quality control of large genome panels. It accepts Illumina paired-end reads from local files, NCBI/ENA SRA accessions, or pre-processed BAM files, and produces fully genotyped and filtered VCF files along with tabulated sample statistics and an HTML report.

We tested **genomepanel_nf** on 100s to 1000s of samples from plant, animal and fungal species with reference genomes in single-digit Gb sizes. Please report any issues or share feature requests on the [GitHub Issues](https://github.com/crolllab/genomepanel_nf/issues) page.

The main design goals were to parallelize tasks as much as possible by splitting reference genomes into segments for variant calling and downstream processing, and to minimize SLURM resource requests dynamically depending on the dataset. Even very large datasets typically peak at single-digit TBs of temporary storage needs.

## Installation and documentation

See the [Getting started](docs/getting-started.md) guide for installation instructions, example commands and input file formats. The [Configuration](docs/configuration.md) page has a detailed description of all parameters and options. The [Output files](docs/output.md) page describes the output files in detail. The [Resources](docs/resources.md) page has recommendations for hardware requirements and runtime.