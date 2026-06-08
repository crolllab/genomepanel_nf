#!/usr/bin/env nextflow
/*
 * Test: verify that the GenotypeGVCFs JVM -Xmx flag scales correctly with
 * task.memory and task.attempt (80 % of allocated memory).
 *
 * Run with:
 *   nextflow run tests/test_heap_memory.nf -profile singularity
 *
 * Expected output (default memory = 16 GB, maxRetries 6):
 *   attempt 1 → avail_mem = 12800 m  (-Xmx12800m)
 *   attempt 2 → avail_mem = 25600 m  (-Xmx25600m)
 *   attempt 3 → avail_mem = 38400 m  (-Xmx38400m)
 *
 * The process intentionally fails on attempts 1 and 2 (exit 247) so that
 * Nextflow retries and we can observe the heap growing across attempts.
 * On attempt 3 it succeeds and prints the final heap size reported by the JVM.
 */

nextflow.enable.dsl = 2

process TestHeapScaling {
    tag           "attempt ${task.attempt}"
    errorStrategy { task.exitStatus == 247 ? 'retry' : 'terminate' }
    maxRetries    3
    memory        { 16.GB * task.attempt }

    output:
    stdout

    script:
    def avail_mem = (task.memory.mega * 0.8).intValue()
    """
    echo "=== attempt ${task.attempt} ==="
    echo "task.memory   : ${task.memory}"
    echo "avail_mem     : ${avail_mem} MiB  (expect \$(( ${task.attempt} * 16 * 1024 * 80 / 100 )) MiB)"
    echo "Xmx flag used : -Xmx${avail_mem}m"

    # Ask the JVM to report its actual MaxHeapSize
    java -Xmx${avail_mem}m -XX:+PrintFlagsFinal -version 2>&1 \
        | awk '/MaxHeapSize/ { printf "JVM MaxHeapSize  : %d MiB (%.1f GiB)\\n", \$4/1024/1024, \$4/1024/1024/1024 }'

    # Fail on the first two attempts to exercise the retry + memory-scaling path;
    # succeed on attempt 3+ so the pipeline can finish.
    if [ "${task.attempt}" -lt 3 ]; then
        echo "Simulating OOM (exit 247) on attempt ${task.attempt}"
        exit 247
    fi

    echo "SUCCESS on attempt ${task.attempt}"
    """
}

workflow {
    TestHeapScaling() | view
}
