# SRA Download Module - Improvements

## Date: October 2, 2025 (Updated: October 5, 2025)

## Problem
The original `download_SRA.nf` module would abort the entire pipeline when any SRA accession failed to download, even after retry attempts. This was problematic because:
1. Some SRR accessions consistently fail due to NCBI server issues or invalid accessions
2. The pipeline would abort entirely, wasting computation on successful samples
3. Retry logic conflicts existed between Nextflow's `errorStrategy 'retry'` and custom bash retries

## Critical Bug Fix (October 5, 2025)

### Issue Discovered
During production run with 2352 SRR accessions:
- Only 1429 samples reached FastpPE trimming
- **923 samples silently disappeared** without error messages
- No failures were reported in logs
- Root cause: `optional: true` outputs caused silent data loss during channel mixing

### Technical Explanation
When a process has `optional: true` outputs:
1. Nextflow treats missing files as "valid empty channels"
2. During channel `.mix()` operations, empty outputs are silently dropped
3. No error/warning is generated because Nextflow considers this normal behavior
4. Result: **Silent sample loss** that's invisible to users and logs

### Solution Implemented
1. **Removed all `optional: true` declarations** from process outputs
2. **Added `.download_status` marker file** to every download (SUCCESS/FAILED)
3. **Created dummy fastq files** for failed downloads (satisfy output requirements)
4. **Explicit filtering in workflow** using `.filter()` on status file content
5. **Added `log.warn` messages** when excluding failed downloads
6. **Updated summary process** to count and report all attempts

### Key Changes

#### Process Output Structure
```groovy
# Old (caused silent data loss):
output:
tuple val(srr), path("${srr}_*.fastq"), optional: true, emit: reads
path "failed_${srr}.txt", optional: true, emit: failures

# New (explicit tracking):
output:
tuple val(srr), path("${srr}_*.fastq"), path(".download_status"), emit: reads
```

#### Workflow Filtering
```groovy
# New explicit filtering in workflow:
sra_pe_filtered = SRAdownloadPE.out.reads
    .filter { srr, fastq_files, status_file ->
        def status_content = status_file.text.trim()
        def is_success = status_content.startsWith("SUCCESS")
        
        if (!is_success) {
            log.warn "Excluding failed PE download: ${srr}"
        }
        
        return is_success
    }
    .map { srr, fastq_files, status_file -> 
        [srr, fastq_files[0], fastq_files[1]]
    }
```

#### Status File Content
```bash
# Success:
SUCCESS

# Failure:
FAILED
Download failed after 3 attempts
---
[last 5 lines of error log]
```

### Result
- ✅ All input SRR accessions are now accounted for
- ✅ Failed downloads generate warning messages during workflow execution
- ✅ `NCBI_download_summary.tsv` shows complete breakdown (successes + failures)
- ✅ No silent data loss possible
- ✅ Downstream processes receive only successfully downloaded samples

## Original Solution (October 2, 2025)

### Simplified Retry Logic
- Removed conflicting Nextflow-level retries (`maxRetries 3`)
- Kept 3 internal retry attempts with 30-second pauses
- Added timeouts to prevent hanging (5 min for prefetch, 10 min for fasterq-dump)

### Better Failure Tracking
- Creates `NCBI_download_summary.tsv` listing all failed accessions
- Includes last 5 lines of error logs for debugging
- Provides complete summary with success/failure counts

### Graceful Failure Handling
- Changed `errorStrategy` from `'retry'` to `'ignore'`
- Always exits with `exit 0` (failures tracked via status files)
- Failed downloads don't block pipeline execution

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

Expected result: 
- Pipeline completes successfully with valid accessions processed
- Invalid ones logged in `NCBI_download_summary.tsv`
- Workflow logs show: `WARN Excluding failed PE download: INVALID_SRR_12345`

## Backwards Compatibility

⚠️ **Breaking Change**: Output structure changed
- Old: `tuple val(srr), path("*.fastq"), optional: true`
- New: `tuple val(srr), path("*.fastq"), path(".download_status")`

**Migration**: Workflow automatically updated to handle new 3-tuple structure with explicit filtering. No user action required for existing pipelines.

## Files Modified

1. **`modules/download_SRA.nf`**
   - Removed `optional: true` from all outputs
   - Added `.download_status` file to every download
   - Create dummy fastq files for failed downloads
   - Enhanced error logging in status files

2. **`workflows/variant_calling_wf.nf`**
   - Added explicit `.filter()` operations on downloaded reads
   - Added `log.warn` messages for excluded samples
   - Collect status files for summary reporting
   - Map 3-tuple back to 2-tuple after filtering

3. **`.github/copilot-instructions.md`**
   - Updated SRA download failure handling section
   - Added warning about `optional: true` causing data loss
   - Documented status file mechanism

## Production Impact

For the affected run (2352 SRR accessions → 1429 processed):
- The 923 missing samples likely had actual download failures
- Old code: Silently dropped, no warning, appeared successful
- New code: Would show 923 `log.warn` messages + entries in summary TSV
- Users can now investigate why specific accessions failed

## Key Takeaway

**Never use `optional: true` in multi-output processes that feed into channel mixing operations.** It creates invisible data loss that's extremely difficult to debug. Always use explicit marker files + filtering instead.
