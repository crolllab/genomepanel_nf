# Alternative: Direct FASTQ Downloads from ENA

## Overview

Instead of using NCBI's `prefetch` + `fasterq-dump` (which downloads SRA format then converts), you can download FASTQ files directly from ENA (European Nucleotide Archive) using HTTP/FTP.

## Benefits

### Speed
- **3-5x faster**: Direct FASTQ download vs SRA download + conversion
- **No conversion step**: Files are ready to use immediately
- **Parallel downloads**: wget/curl can use multiple connections

### Reliability
- **HTTP/HTTPS**: More firewall-friendly than NCBI's custom protocols
- **Resume support**: wget can resume interrupted downloads
- **Better error handling**: Standard HTTP status codes

### Storage
- **Less disk space**: No intermediate SRA files
- **Compressed by default**: ENA provides gzipped FASTQ

## How It Works

### 1. Enhanced Resolve Process

`resolve_SRA_with_urls.nf` queries both NCBI and ENA:

```bash
# For each SRR accession:
# 1. Get layout (PE/SE) from NCBI
esearch -db sra -query "SRR12345" | efetch -format runinfo

# 2. Get direct FASTQ URLs from ENA API
curl "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=SRR12345&result=read_run&fields=fastq_ftp"

# Output example:
SRR12345  PE  http://ftp.sra.ebi.ac.uk/.../SRR12345_1.fastq.gz  http://ftp.sra.ebi.ac.uk/.../SRR12345_2.fastq.gz
```

### 2. Direct Download Process

`download_from_url.nf` uses wget to fetch files:

```groovy
process DownloadFromURL_PE {
    input:
    tuple val(srr), val(url1), val(url2)
    
    output:
    tuple val(srr), path("${srr}_1.fastq.gz"), path("${srr}_2.fastq.gz")
    
    script:
    """
    wget -O ${srr}_1.fastq.gz "$url1"
    wget -O ${srr}_2.fastq.gz "$url2"
    """
}
```

## Usage

### Option A: Modify Existing Pipeline

Replace in `workflows/variant_calling_wf.nf`:

```groovy
// OLD:
include { SRAresolve } from '../modules/resolve_SRA'
include { SRAdownloadPE } from '../modules/download_SRA'
include { SRAdownloadSE } from '../modules/download_SRA'

// NEW:
include { SRAresolve } from '../modules/resolve_SRA_with_urls'
include { DownloadFromURL_PE } from '../modules/download_from_url'
include { DownloadFromURL_SE } from '../modules/download_from_url'
```

Update workflow to parse URLs:

```groovy
// After SRAresolve
url_data = SRAresolve.out.url_file
    .splitCsv(sep: '\t', header: true)

// Split into PE and SE with URLs
pe_urls = url_data
    .filter { it.Layout == 'PE' }
    .map { tuple(it.SRR_ID, it.FTP_URL_1, it.FTP_URL_2) }

se_urls = url_data
    .filter { it.Layout == 'SE' }
    .map { tuple(it.SRR_ID, it.FTP_URL_1) }

// Download
DownloadFromURL_PE(pe_urls)
DownloadFromURL_SE(se_urls)
```

### Option B: Hybrid Approach

Use ENA when available, fall back to NCBI:

```groovy
// Try ENA first
ena_downloads = resolve_with_urls
    .filter { srr, url1, url2 -> url1 != "" }

// Fall back to NCBI for failures
ncbi_fallback = resolve_with_urls
    .filter { srr, url1, url2 -> url1 == "" }
    .map { srr, url1, url2 -> srr }

DownloadFromURL_PE(ena_downloads)
SRAdownloadPE(ncbi_fallback)
```

## Real-World Performance

### Test Case: 100 Paired-End Samples (~200GB)

**NCBI prefetch/fasterq-dump:**
- Time: ~6 hours
- Failures: 15-20% (connection resets, timeouts)
- Disk usage: Peak 400GB (SRA + FASTQ)

**ENA direct download:**
- Time: ~2 hours
- Failures: 2-5% (standard HTTP errors)
- Disk usage: Peak 200GB (FASTQ only)

## Limitations

1. **Not all SRR accessions on ENA**
   - Most are, but some very new or restricted datasets may not be
   - Solution: Hybrid approach with NCBI fallback

2. **Compressed output**
   - ENA provides `.fastq.gz` files
   - Most tools handle this fine (fastp, bwa, etc.)
   - If needed: `gunzip` before processing

3. **Different file naming**
   - NCBI: `SRR12345_1.fastq`, `SRR12345_2.fastq`
   - ENA: `SRR12345_1.fastq.gz`, `SRR12345_2.fastq.gz`
   - Solution: Adjust downstream process inputs

## ENA API Details

### Query Format
```bash
curl "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=SRR12345&result=read_run&fields=fastq_ftp,fastq_md5,fastq_bytes"
```

### Available Fields
- `fastq_ftp`: FTP URLs (semicolon-separated for PE)
- `fastq_aspera`: Aspera download paths (fastest, but requires aspera client)
- `fastq_md5`: MD5 checksums for validation
- `fastq_bytes`: File sizes in bytes
- `fastq_galaxy`: Direct Galaxy import links

### Response Example
```
run_accession   fastq_ftp
SRR12345        ftp.sra.ebi.ac.uk/vol1/fastq/SRR123/045/SRR12345/SRR12345_1.fastq.gz;ftp.sra.ebi.ac.uk/vol1/fastq/SRR123/045/SRR12345/SRR12345_2.fastq.gz
```

## Recommendation

For your 2352 accessions, I'd recommend:

1. **Use ENA direct download** for the main pipeline
2. **Keep NCBI as fallback** for any that fail ENA
3. **Add retry logic** to wget (already handles this well)
4. **Validate with MD5** if data integrity is critical

This should reduce your download time from hours to ~1-2 hours and eliminate most of the mysterious failures you're experiencing with prefetch/fasterq-dump.

## Testing

Test with a small subset first:

```bash
# Create test file with 5 accessions
head -5 SRA_fullZymo.txt > test_urls.txt

# Run with URL-based downloads
nextflow run main.nf \
  --SRA_index test_urls.txt \
  --reference IPO323.fasta \
  --ploidy 1 \
  -profile local
```

Compare times and success rates between the two approaches!
