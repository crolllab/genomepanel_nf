// Delete the intermediate files a task consumed, once Nextflow has accepted
// that task's output.
//
// Each read-processing step used to `rm` its own inputs at the end of its
// script. That is not safe to retry: the script can succeed, delete its input,
// and the task still be reported as failed -- on 2026-09-18 a storage stall on
// the compute node made Nextflow's job wrapper exit 141 after addRG had
// finished, every retry then found the sorted BAM gone ("Cannot read
// non-existent file"), and the whole run aborted. Deleting from the workflow
// instead, on the task's emitted output, means the files are only removed
// after Nextflow has recorded the task as successful; a failed or retried
// attempt always finds its inputs intact.
//
// Only paths inside the work directory are ever touched, and symlinks are
// removed as links (never followed), so user-supplied reads or BAMs cannot be
// deleted however they reach this function. A path that is already gone --
// e.g. a cached task re-emitting its output under -resume -- is skipped.
def deleteIntermediates(consumed) {
    def work_root = workflow.workDir.toAbsolutePath().normalize()
    consumed.each { p ->
        def target = file(p.toString()).toAbsolutePath().normalize()
        if (!target.startsWith(work_root)) {
            return
        }
        try {
            java.nio.file.Files.deleteIfExists(target)
        }
        catch (Exception e) {
            log.warn "Could not delete intermediate file ${target}: ${e.message}"
        }
    }
}
