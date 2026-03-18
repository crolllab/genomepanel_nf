process PipelineStatistics {
    tag "Generating pipeline execution statistics"
    memory '8GB'
    cpus 1
    
    publishDir params.outdir, mode: 'copy'
    
    input:
    val ready
    
    output:
    path "pipeline_execution_stats.txt"
    path "pipeline_execution_stats.tsv"
    
    shell:
    '''
    #!/bin/bash
    set -euo pipefail
    
    OUTFILE="pipeline_execution_stats.txt"
    TSV_FILE="pipeline_execution_stats.tsv"
    OUTDIR="!{params.outdir}"
    LAUNCH_DIR="!{workflow.launchDir}"
    OUTDIR="${OUTDIR%/}"

    if [[ "$OUTDIR" = /* ]]; then
        TRACE_FILE="$OUTDIR/pipeline_trace.txt"
    else
        TRACE_FILE="$LAUNCH_DIR/$OUTDIR/pipeline_trace.txt"
    fi
    
    echo "=================================================================" > $OUTFILE
    echo "  Nextflow Pipeline - Process Statistics" >> $OUTFILE
    echo "  Generated: $(date)" >> $OUTFILE
    echo "=================================================================" >> $OUTFILE
    echo "" >> $OUTFILE
    
    echo -e "Process\\tCount\\tAvg_Seconds\\tMin_Seconds\\tMax_Seconds" > $TSV_FILE
    
    if [ ! -s "$TRACE_FILE" ]; then
        echo "WARNING: Trace file not found or empty: $TRACE_FILE" >> $OUTFILE
        echo "No process statistics were generated." >> $OUTFILE
        echo "" >> $OUTFILE
        echo "=================================================================" >> $OUTFILE
        echo "Notes:" >> $OUTFILE
        echo "  - Statistics are derived from pipeline_trace.txt" >> $OUTFILE
        echo "  - Ensure trace is enabled and run has completed enough tasks" >> $OUTFILE
        echo "=================================================================" >> $OUTFILE
        echo "Statistics generated with warnings"
        exit 0
    fi

    parsed_file=$(mktemp)

    # Parse completed successful tasks and convert duration/realtime strings to seconds.
    awk -F '\t' '
    function trim(s) {
        gsub(/^[ \t]+|[ \t]+$/, "", s)
        return s
    }

    function to_seconds(raw,    s, n, i, tok, m, val, unit, total) {
        s = trim(raw)
        if (s == "") return -1

        total = 0
        n = split(s, tok, / +/)
        for (i = 1; i <= n; i++) {
            if (tok[i] == "") continue

            if (match(tok[i], /^([0-9]*\.?[0-9]+)(ms|s|m|h|d)$/, m)) {
                val = m[1] + 0
                unit = m[2]
                if (unit == "ms") total += (val / 1000)
                else if (unit == "s") total += val
                else if (unit == "m") total += (val * 60)
                else if (unit == "h") total += (val * 3600)
                else if (unit == "d") total += (val * 86400)
            }
            else if (tok[i] ~ /^[0-9]*\.?[0-9]+$/) {
                total += (tok[i] + 0)
            }
            else {
                return -1
            }
        }

        return total
    }

    NR == 1 { next }

    {
        process_name = $4
        status = $7
        exit_code = $8
        realtime = $13
        duration = $12

        sub(/^.*:/, "", process_name)

        sec = to_seconds(realtime)
        if (sec < 0) sec = to_seconds(duration)

        if (status == "COMPLETED" && exit_code == "0" && sec >= 0) {
            printf "%s\t%.6f\n", process_name, sec
        }
    }
    ' "$TRACE_FILE" > "$parsed_file"

    get_stats() {
        local process_id="$1"
        local display_name="$2"
        local stats
        local count avg min max

        stats=$(awk -F '\t' -v p="$process_id" '
        $1 == p {
            count++
            sum += $2
            if (count == 1 || $2 < min) min = $2
            if (count == 1 || $2 > max) max = $2
        }
        END {
            if (count > 0) {
                printf "%d\t%.0f\t%.0f\t%.0f", count, (sum / count), min, max
            }
        }
        ' "$parsed_file")

        if [ -n "$stats" ]; then
            IFS=$'\t' read -r count avg min max <<< "$stats"

            avg_m=$((avg / 60))
            avg_s=$((avg % 60))
            min_m=$((min / 60))
            min_s=$((min % 60))
            max_m=$((max / 60))
            max_s=$((max % 60))

            printf "%-30s Count: %4d   Avg: %2dm%02ds   Range: %dm%ds - %dm%ds\\n" \\
                "$display_name" "$count" "$avg_m" "$avg_s" "$min_m" "$min_s" "$max_m" "$max_s" >> "$OUTFILE"

            echo -e "$display_name\t$count\t$avg\t$min\t$max" >> "$TSV_FILE"
        else
            printf "%-30s Count: %4d   Avg: %s   Range: %s - %s\\n" \\
                "$display_name" 0 "n/a" "n/a" "n/a" >> "$OUTFILE"

            echo -e "$display_name\t0\t0\t0\t0" >> "$TSV_FILE"
        fi
    }
    
    echo "Process                        Count    Average Time    Range (Min - Max)" >> $OUTFILE
    echo "-----------------------------------------------------------------------------" >> $OUTFILE
    
    get_stats "SRAdownloadPE" "SRA Download (PE)"
    get_stats "SRAdownloadSE" "SRA Download (SE)"
    get_stats "trimSequencesPE" "FASTP Trimming (PE)"
    get_stats "trimSequencesSE" "FASTP Trimming (SE)"
    get_stats "bwaMap" "BWA Mapping"
    get_stats "samtoolsSort" "Samtools Sort"
    get_stats "addRG" "Picard AddReadGroups"
    get_stats "dupRemoval" "Picard MarkDuplicates"
    get_stats "GATKHC" "GATK HaplotypeCaller"
    get_stats "CombineGVCFs" "GATK CombineGVCFs"
    get_stats "GenotypeGVCFs" "GATK GenotypeGVCFs"
    get_stats "FilterVCFs" "GATK FilterVariants"
    get_stats "CleanVCFs" "BCFtools CleanVCF"
    get_stats "ConcatVCFs" "BCFtools Concat VCF"
    get_stats "ConcatCleanVCFs" "BCFtools Concat Clean"
    get_stats "PopGenVCF" "VCFtools PopGen Filter"
    
    echo "" >> $OUTFILE
    echo "=================================================================" >> $OUTFILE
    echo "Notes:" >> $OUTFILE
    echo "  - Statistics from completed tasks only" >> $OUTFILE
    echo "  - Times are from Nextflow trace realtime/duration fields" >> $OUTFILE
    echo "  - Trace file: $TRACE_FILE" >> $OUTFILE
    echo "=================================================================" >> $OUTFILE
    
    rm -f "$parsed_file"

    echo "Statistics generated successfully"
    '''
}
