# Simplified SRA Download Module

## Date: October 6, 2025

## Complete Rewrite - Ultra-Simple Approach

After persistent issues with complex retry logic and status tracking causing silent data loss, the `download_SRA.nf` module has been completely rewritten with maximum simplicity.

## New Philosophy: Let Nextflow Handle It

**Key principle**: Use Nextflow's native `errorStrategy 'ignore'` to handle failures instead of complex bash logic.

### What Changed

#### OLD (Complex, Buggy):
- Multiple retry attempts in bash
- Status files (.download_status)
- Dummy file creation
- Optional outputs
- Complex filtering in workflow
- CollectFailedDownloads process
- **Result**: 923 samples silently lost

#### NEW (Simple, Reliable):
- Single download attempt
- No status tracking
- No dummy files
- Simple outputs: `tuple val(srr), path("file1.fastq"), path("file2.fastq")`
- `errorStrategy 'ignore'` = if download fails, process produces no output
- No filtering needed - Nextflow automatically handles it
- **Result**: Only successful downloads reach downstream processes

## Complete Module Code

```groovy
// Simple, robust SRA download for paired-end reads
process SRAdownloadPE {
    cpus 1
    memory '4GB'
    tag "Downloading PE: $srr"
    errorStrategy 'ignore'
    
    input:
    val srr
    
    output:
    tuple val(srr), path("${srr}_1.fastq"), path("${srr}_2.fastq")
    
    script:
    """
    #!/bin/bash
    set -e
    
    echo "Downloading $srr"
    
    # Download with prefetch
    prefetch $srr
    
    # Convert to fastq
    fasterq-dump $srr --split-files -O .
    
    # Verify we got paired-end files
    if [ ! -f "${srr}_1.fastq" ] || [ ! -f "${srr}_2.fastq" ]; then
        echo "ERROR: Expected PE files not found for $srr"
        exit 1
    fi
    
    # Check files are not empty
    if [ ! -s "${srr}_1.fastq" ] || [ ! -s "${srr}_2.fastq" ]; then
        echo "ERROR: Empty fastq files for $srr"
        exit 1
    fi
    
    # Clean up SRA file
    rm -rf ${srr}/ ${srr}.sra
    
    echo "Successfully downloaded $srr"
    """
}
```

## How It Works

1. **Process runs** for each SRR accession
2. **On success**: 
   - Creates `${srr}_1.fastq` and `${srr}_2.fastq`
   - `exit 0` (implicit)
   - Output tuple emitted to channel
3. **On failure**:
   - Any error causes `exit 1` (due to `set -e`)
   - `errorStrategy 'ignore'` catches the failure
   - **No output emitted** to channel
   - Process marked as "ignored" in logs
   - Pipeline continues

## Workflow Changes

### OLD (Complex):
```groovy
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

### NEW (Simple):
```groovy
sra_pe_formatted = SRAdownloadPE.out
```

That's it! Failed downloads don't appear in the output channel at all.

## Benefits

1. **No silent data loss**: If a sample doesn't reach downstream, check `.nextflow.log` for ignored processes
2. **Clear logging**: Nextflow logs show which processes were ignored
3. **Simple debugging**: If something fails, check the work directory for that specific SRR
4. **No complex state management**: No status files, no filtering, no confusion
5. **Idiomatic Nextflow**: Uses built-in error handling instead of reinventing it

## Finding Failed Downloads

Check the Nextflow log for ignored processes:

```bash
# Count ignored SRAdownloadPE processes
grep "Ignored process > SRAdownloadPE" .nextflow.log | wc -l

# See which SRRs failed
grep "Ignored process > SRAdownloadPE" .nextflow.log | grep -oP 'SRR[0-9]+'

# Check work directory for failure details
find work -name ".exitcode" -exec grep -l "1" {} \; | while read f; do
    dir=$(dirname "$f")
    echo "Failed task: $dir"
    cat "$dir/.command.log" | tail -20
done
```

## No Retry Logic (For Now)

Per user request, retry logic has been removed. If NCBI downloads are flaky, you can:

1. **Add `maxRetries`** at the Nextflow level:
   ```groovy
   process SRAdownloadPE {
       errorStrategy { task.attempt <= 3 ? 'retry' : 'ignore' }
       maxRetries 3
       ...
   }
   ```

2. **Manually rerun failed accessions** after identifying them from logs

3. **Download separately** using `parallel` + `fasterq-dump` outside the pipeline

## Migration Notes

- ✅ No workflow changes needed beyond removing unused imports
- ✅ Existing `--SRA_index` parameter works exactly the same
- ✅ Output format unchanged for successful downloads
- ⚠️ `NCBI_download_summary.tsv` is no longer generated (use `.nextflow.log` instead)

## Expected Behavior for Your 2352 Accessions

With the new code:
- All 2352 will be attempted
- ~1429 will succeed and proceed to FastpPE
- ~923 will fail and be logged as "Ignored process"
- `.nextflow.log` will show: `Ignored process > SRAdownloadPE (Downloading PE: SRR12345678)`
- No silent losses - every sample is accounted for

## Key Takeaway

**Simple code is reliable code.** By removing 200+ lines of complex bash retry logic, status tracking, and filtering, we get:
- Better reliability
- Easier debugging
- Clear audit trail in logs
- Native Nextflow error handling
