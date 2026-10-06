process RQualPlotting {
    tag "Generating QC report"
    // Retry only on memory/kill exits (memory scales with the attempt). An R
    // error recurs identically on every retry, so fail at once instead of
    // resubmitting six times with ever larger memory requests. An OOM kill
    // reported with another exit status is mapped to 247 below, as in
    // GenomicsDBImport.
    errorStrategy { task.exitStatus in [137, 143, 247] ? 'retry' : 'finish' }
    maxRetries 6
    publishDir "${params.outdir}/10_reports", mode: 'copy'

    input:
    path concat_vcf
    path fastp_tsv
    path bwa_tsv
    path ignored_samples
    path r_script
    val  pipeline_version
    val  pipeline_start

    output:
    path "pipeline_report.html", emit: report

    script:
    """
    oom_kills() {
        local ev="/sys/fs/cgroup\$(sed -n 's/^0:://p' /proc/self/cgroup)/memory.events"
        if [ -r "\$ev" ]; then awk '\$1 == "oom_kill" { print \$2 }' "\$ev"; else echo 0; fi
    }
    oom_before=\$(oom_kills)

    echo -e "version\t${pipeline_version}" > pipeline_meta.txt
    echo -e "report_date\t\$(date '+%Y-%m-%d %H:%M')" >> pipeline_meta.txt
    echo -e "pipeline_start\t${pipeline_start}" >> pipeline_meta.txt
    Rscript ${r_script} || {
        rc=\$?
        if [ "\$(oom_kills)" -gt "\$oom_before" ]; then
            echo "Exit status \$rc coincides with a cgroup OOM kill; reporting it as 247" >&2
            rc=247
        fi
        exit \$rc
    }
    """
}
