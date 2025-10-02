# SRA Download Module - Improvements

## Date: October 2, 2025

## Problem
The original `download_SRA.nf` module would abort the entire pipeline when any SRA accession failed to download, even after retry attempts. This was problematic because:
1. Some SRR accessions consistently fail due to NCBI server issues or invalid accessions
2. The pipeline would abort entirely, wasting computation on successful samples
3. Retry logic conflicts existed between Nextflow's `errorStrategy 'retry'` and custom bash retries

## Solution
Completely refactored both `SRAdownloadPE` and `SRAdownloadSE` processes to be failure-tolerant:

### Key Changes

1. **Graceful Failure Handling**
   - Changed `errorStrategy` from `'retry'` to `'ignore'`
   - Removed `exit 1` on failures - now always exits with `exit 0`
   - Failed downloads are logged but don't block pipeline execution

2. **Simplified Retry Logic**
   - Removed Nextflow-level retries (was: `maxRetries 3`)
   - Kept internal bash retry loop (3 attempts with 30-second pauses)
   - This eliminates duplicate retry behavior

3. **Added Timeouts**
   - `prefetch`: 300 seconds (5 minutes)
   - `fasterq-dump`: 600 seconds (10 minutes)
   - Prevents indefinite hanging on network issues

4. **Named Output Channels**
   ```groovy
   output:
   tuple val(srr), path("${srr}_*.fastq"), optional: true, emit: reads
   path "failed_${srr}.txt", optional: true, emit: failures
   ```
   - More explicit than array indexing (`out[0]`, `out[1]`)
   - Better debugging and code readability

5. **Enhanced Failure Reporting**
   - Failure files include last 5 lines of error logs
   - `NCBI_download_summary.tsv` created only when failures occur
   - Summary includes total count of failed downloads

6. **Improved File Validation**
   - PE: Verifies at least 2 fastq files exist and are non-empty
   - SE: Handles both `${srr}.fastq` and `${srr}_1.fastq` naming variations
   - Cleans up partial/temporary files more reliably

## Workflow Updates

Updated `workflows/variant_calling_wf.nf` to use named outputs:
```groovy
# Old (array indexing):
sra_pe_formatted = SRAdownloadPE.out[0].map { ... }
pe_failures = SRAdownloadPE.out[1].collect()

# New (named outputs):
sra_pe_formatted = SRAdownloadPE.out.reads.map { ... }
pe_failures = SRAdownloadPE.out.failures.collect()
```

## Expected Behavior

### Successful Downloads
- Files flow normally to trimming step
- No failure file created
- Process completes with exit code 0

### Failed Downloads
- Process completes with exit code 0 (doesn't abort pipeline)
- Creates `failed_${srr}.txt` with error details
- No fastq files emitted (due to `optional: true`)
- Sample is excluded from downstream analysis
- Failure logged in `NCBI_download_summary.tsv`

### Example Output
```
NCBI_download_summary.tsv:
SRR_ID          Type    Error_Details
SRR12345678     PE      Download failed after 3 attempts
                        Last error:
                        Connection reset by peer
                        Prefetch timeout
====================================
Total failed downloads: 1
Pipeline continued with successfully downloaded samples
```

## Testing Recommendations

Test with a mix of valid and invalid SRR accessions:
```bash
# Create test file with known-good and known-bad accessions
cat > test_SRA.txt << EOF
SRR24910574
SRR24910575
INVALID_SRR_12345
SRR_DOES_NOT_EXIST
EOF

# Run pipeline - should continue despite 2 failures
nextflow run main.nf -profile local \
  --reference IPO323.fasta --ploidy 1 \
  --SRA_index test_SRA.txt \
  --NCBI_API_key $KEY \
  --outdir test_output
```

Expected result: Pipeline completes successfully with valid accessions processed and invalid ones logged in summary file.

## Backwards Compatibility

✅ Fully backwards compatible
- No changes to input parameters
- No changes to successful output format
- Workflow changes only affect internal channel routing
- Existing pipelines will benefit from improved robustness automatically
