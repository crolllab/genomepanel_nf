process PipelineStatistics {
    tag "Generating pipeline execution statistics"
    memory '8GB'
    cpus 1
    time '30m'
    
    publishDir params.outdir, mode: 'copy'
    
    input:
    val ready  // Dummy input to ensure this runs at the end
    
    output:
    path "pipeline_execution_stats.txt", emit: stats
    path "pipeline_execution_stats.tsv", emit: stats_tsv
    path "pipeline_failures_summary.txt", emit: failures
    
    script:
    """
    #!/bin/bash
    set -e
    
    # Output files
    OUTFILE="pipeline_execution_stats.txt"
    TSV_FILE="pipeline_execution_stats.tsv"
    FAIL_FILE="pipeline_failures_summary.txt"
    
    echo "==================================================================="  > \$OUTFILE
    echo "  Nextflow Pipeline - Process Completion Time Analysis"          >> \$OUTFILE
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')"                      >> \$OUTFILE
    echo "==================================================================" >> \$OUTFILE
    echo ""                                                                  >> \$OUTFILE
    
    # Initialize failure summary file
    echo "==================================================================="  > \$FAIL_FILE
    echo "  Pipeline Failures & Ignored Samples Summary"                   >> \$FAIL_FILE
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')"                      >> \$FAIL_FILE
    echo "==================================================================" >> \$FAIL_FILE
    echo ""                                                                  >> \$FAIL_FILE
    
    # Function to analyze process failures and ignored tasks
    analyze_failures() {
        local process_pattern=\$1
        local process_name=\$2
        
        local total=0
        local completed=0
        local failed=0
        local failed_samples=""
        
        # Find ALL work dirs for this process
        while IFS= read -r dir; do
            if [ -f "\$dir/.command.run" ]; then
                # Check if this is the right process type (more flexible pattern matching)
                if grep -qE "(variant_calling:)?\$process_pattern" "\$dir/.command.run" 2>/dev/null; then
                    total=\$((total + 1))
                    
                    if [ -f "\$dir/.exitcode" ]; then
                        exitcode=\$(cat "\$dir/.exitcode")
                        
                        if [ "\$exitcode" -eq 0 ]; then
                            completed=\$((completed + 1))
                        else
                            failed=\$((failed + 1))
                            
                            # Try to extract sample ID from command
                            sample_id=""
                            if [ -f "\$dir/.command.sh" ]; then
                                # Look for common patterns: ERR/SRR IDs or sample names
                                sample_id=\$(grep -oE "(ERR|SRR|DRR)[0-9]+" "\$dir/.command.sh" 2>/dev/null | head -1)
                                if [ -z "\$sample_id" ]; then
                                    # Try to extract from file names in command
                                    sample_id=\$(grep -oE "[A-Za-z0-9_-]+_[12]\.fastq" "\$dir/.command.sh" 2>/dev/null | head -1 | sed 's/_[12]\.fastq//')
                                fi
                            fi
                            
                            # Get error message if available
                            error_msg=""
                            if [ -f "\$dir/.command.err" ]; then
                                error_msg=\$(grep -E "ERROR|error|Error|failed|Failed" "\$dir/.command.err" 2>/dev/null | tail -1 | cut -c 1-80)
                            fi
                            
                            if [ -n "\$sample_id" ]; then
                                failed_samples="\${failed_samples}\n    - \${sample_id} (exit code: \${exitcode})"
                                if [ -n "\$error_msg" ]; then
                                    failed_samples="\${failed_samples}\n      Error: \${error_msg}"
                                fi
                            else
                                failed_samples="\${failed_samples}\n    - Unknown sample (exit code: \${exitcode}, dir: \${dir##*/})"
                            fi
                        fi
                    fi
                fi
            fi
        done < <(find ${workflow.workDir} -maxdepth 3 -type d -name "[a-f0-9]*" 2>/dev/null)
        
        if [ \$total -gt 0 ]; then
            if [ \$failed -gt 0 ]; then
                printf "\\n%-30s Total: %4d   Completed: %4d   Failed/Ignored: %4d\\n" \\
                    "\$process_name" "\$total" "\$completed" "\$failed" >> \$FAIL_FILE
                echo -e "\$failed_samples" >> \$FAIL_FILE
            fi
        fi
        
        # Return counts for summary
        echo "\$total:\$completed:\$failed"
    }
    
    # Function to analyze process times
    analyze_process() {
        local process_pattern=\$1
        local process_name=\$2
        
        # Find ALL work dirs for this process (no sampling limit)
        # Search all subdirectories in the work directory
        times=""
        count=0
        
        # Use find to get all directories with required files, then filter by process
        while IFS= read -r dir; do
            if [ -f "\$dir/.command.run" ] && [ -f "\$dir/.command.begin" ] && [ -f "\$dir/.exitcode" ]; then
                # Check if this is the right process type (more flexible pattern matching)
                if grep -qE "(variant_calling:)?\$process_pattern" "\$dir/.command.run" 2>/dev/null; then
                    exitcode=\$(cat "\$dir/.exitcode")
                    if [ "\$exitcode" -eq 0 ]; then
                        begin=\$(stat -c %Y "\$dir/.command.begin" 2>/dev/null)
                        end=\$(stat -c %Y "\$dir/.exitcode" 2>/dev/null)
                        
                        if [ -n "\$begin" ] && [ -n "\$end" ]; then
                            duration=\$((end - begin))
                            # Sanity check: 0 < duration < 24 hours
                            if [ \$duration -gt 0 ] && [ \$duration -lt 86400 ]; then
                                times="\$times \$duration"
                                count=\$((count + 1))
                            fi
                        fi
                    fi
                fi
            fi
        done < <(find ${workflow.workDir} -maxdepth 3 -type d -name "[a-f0-9]*" 2>/dev/null)
        
        if [ -n "\$times" ] && [ \$count -gt 0 ]; then
            sum=0
            min=999999
            max=0
            for t in \$times; do
                sum=\$((sum + t))
                [ \$t -lt \$min ] && min=\$t
                [ \$t -gt \$max ] && max=\$t
            done
            avg=\$((sum / count))
            
            # Format times
            avg_h=\$((avg / 3600))
            avg_m=\$(((avg % 3600) / 60))
            avg_s=\$((avg % 60))
            
            min_h=\$((min / 3600))
            min_m=\$(((min % 3600) / 60))
            min_s=\$((min % 60))
            
            max_h=\$((max / 3600))
            max_m=\$(((max % 3600) / 60))
            max_s=\$((max % 60))
            
            # Format average time string
            if [ \$avg_h -gt 0 ]; then
                avg_str=\$(printf "%2dh %02dm %02ds" \$avg_h \$avg_m \$avg_s)
            elif [ \$avg_m -gt 0 ]; then
                avg_str=\$(printf "    %2dm %02ds" \$avg_m \$avg_s)
            else
                avg_str=\$(printf "        %2ds" \$avg_s)
            fi
            
            # Format min time string
            if [ \$min_h -gt 0 ]; then
                min_str=\$(printf "%dh%dm%ds" \$min_h \$min_m \$min_s)
            elif [ \$min_m -gt 0 ]; then
                min_str=\$(printf "%dm%ds" \$min_m \$min_s)
            else
                min_str=\$(printf "%ds" \$min_s)
            fi
            
            # Format max time string
            if [ \$max_h -gt 0 ]; then
                max_str=\$(printf "%dh%dm%ds" \$max_h \$max_m \$max_s)
            elif [ \$max_m -gt 0 ]; then
                max_str=\$(printf "%dm%ds" \$max_m \$max_s)
            else
                max_str=\$(printf "%ds" \$max_s)
            fi
            
            # Print to text file
            printf "%-30s Count: %4d   Avg: %-12s  Range: %-10s - %-10s\\n" \\
                "\$process_name" "\$count" "\$avg_str" "\$min_str" "\$max_str" >> \$OUTFILE
            
            # Write to TSV
            echo -e "\$process_name\\t\$count\\t\$avg\\t\$min\\t\$max" >> \$TSV_FILE
        fi
    }
    
    # Write TSV header
    echo -e "Process\\tCount\\tAvg_Seconds\\tMin_Seconds\\tMax_Seconds" > \$TSV_FILE
    
    # Analyze failures for each process
    echo "Analyzing failures by pipeline stage..." >> \$FAIL_FILE
    echo "---------------------------------------------------------------------------------" >> \$FAIL_FILE
    
    # Track overall statistics
    total_samples_started=0
    total_samples_completed=0
    total_samples_failed=0
    
    # Check each stage
    for stage_info in "SRAdownloadPE:SRA Download (PE)" "SRAdownloadSE:SRA Download (SE)" \\
                      "trimSequencesPE:FASTP Trimming (PE)" "trimSequencesSE:FASTP Trimming (SE)" \\
                      "bwaMap:BWA Mapping" "samtoolsSort:Samtools Sort" \\
                      "addRG:Picard AddReadGroups" "dupRemoval:Picard MarkDuplicates" \\
                      "GATKHC:GATK HaplotypeCaller"; do
        pattern=\${stage_info%%:*}
        name=\${stage_info#*:}
        
        result=\$(analyze_failures "\$pattern" "\$name")
        total=\${result%%:*}
        result=\${result#*:}
        completed=\${result%%:*}
        failed=\${result#*:}
        
        if [ \$total -gt 0 ]; then
            [ \$total -gt \$total_samples_started ] && total_samples_started=\$total
        fi
    done
    
    echo "" >> \$FAIL_FILE
    echo "==================================================================" >> \$FAIL_FILE
    echo "OVERALL SUMMARY" >> \$FAIL_FILE
    echo "==================================================================" >> \$FAIL_FILE
    
    # Count samples at different stages
    download_complete=0
    trim_complete=0
    mapping_complete=0
    variant_complete=0
    
    # Count successful completions at key stages
    while IFS= read -r dir; do
        [ -f "\$dir/.exitcode" ] || continue
        exitcode=\$(cat "\$dir/.exitcode")
        [ "\$exitcode" -eq 0 ] || continue
        
        if [ -f "\$dir/.command.run" ]; then
            if grep -qE "(variant_calling:)?SRAdownload" "\$dir/.command.run" 2>/dev/null; then
                download_complete=\$((download_complete + 1))
            elif grep -qE "(variant_calling:)?trimSequences" "\$dir/.command.run" 2>/dev/null; then
                trim_complete=\$((trim_complete + 1))
            elif grep -qE "(variant_calling:)?bwaMap" "\$dir/.command.run" 2>/dev/null; then
                mapping_complete=\$((mapping_complete + 1))
            elif grep -qE "(variant_calling:)?GATKHC" "\$dir/.command.run" 2>/dev/null; then
                variant_complete=\$((variant_complete + 1))
            fi
        fi
    done < <(find ${workflow.workDir} -maxdepth 3 -type d -name "[a-f0-9]*" 2>/dev/null)
    
    echo "" >> \$FAIL_FILE
    echo "Pipeline Stage Completion:" >> \$FAIL_FILE
    echo "  Downloaded:       \$download_complete samples" >> \$FAIL_FILE
    echo "  Trimmed:          \$trim_complete samples" >> \$FAIL_FILE
    echo "  Mapped:           \$mapping_complete samples" >> \$FAIL_FILE
    echo "  Variant Called:   \$variant_complete samples" >> \$FAIL_FILE
    
    # Calculate losses at each stage
    if [ \$download_complete -gt 0 ]; then
        lost_trim=\$((download_complete - trim_complete))
        lost_map=\$((trim_complete - mapping_complete))
        lost_var=\$((mapping_complete - variant_complete))
        
        echo "" >> \$FAIL_FILE
        echo "Sample Loss by Stage:" >> \$FAIL_FILE
        [ \$lost_trim -gt 0 ] && echo "  Lost at Trimming:     \$lost_trim samples" >> \$FAIL_FILE
        [ \$lost_map -gt 0 ] && echo "  Lost at Mapping:      \$lost_map samples" >> \$FAIL_FILE
        [ \$lost_var -gt 0 ] && echo "  Lost at Variant Call: \$lost_var samples" >> \$FAIL_FILE
        
        if [ \$lost_trim -eq 0 ] && [ \$lost_map -eq 0 ] && [ \$lost_var -eq 0 ]; then
            echo "  ✓ No samples lost - all samples completed successfully!" >> \$FAIL_FILE
        fi
    fi
    
    echo "" >> \$FAIL_FILE
    echo "==================================================================" >> \$FAIL_FILE
    echo "Notes:" >> \$FAIL_FILE
    echo "  - Processes with errorStrategy 'ignore' continue despite failures" >> \$FAIL_FILE
    echo "  - Failed samples are excluded from downstream analysis" >> \$FAIL_FILE
    echo "  - Check individual error logs in work directories for details" >> \$FAIL_FILE
    echo "==================================================================" >> \$FAIL_FILE
    
    # Header for text file
    echo "Process                        Count    Average Time      Range (Min - Max)" >> \$OUTFILE
    echo "---------------------------------------------------------------------------------" >> \$OUTFILE
    
    # Analyze each process type
    analyze_process "SRAdownloadPE" "SRA Download (PE)"
    analyze_process "SRAdownloadSE" "SRA Download (SE)"
    analyze_process "trimSequencesPE" "FASTP Trimming (PE)"
    analyze_process "trimSequencesSE" "FASTP Trimming (SE)"
    analyze_process "bwaMap" "BWA Mapping"
    analyze_process "samtoolsSort" "Samtools Sort"
    analyze_process "addRG" "Picard AddReadGroups"
    analyze_process "dupRemoval" "Picard MarkDuplicates"
    analyze_process "GATKHC" "GATK HaplotypeCaller"
    analyze_process "CombineGVCFs" "GATK CombineGVCFs"
    analyze_process "GenotypeGVCFs" "GATK GenotypeGVCFs"
    analyze_process "FilterVCFs" "GATK FilterVariants"
    analyze_process "CleanVCFs" "BCFtools CleanVCF"
    analyze_process "ConcatVCFs" "BCFtools Concat VCF"
    analyze_process "ConcatCleanVCFs" "BCFtools Concat Clean VCF"
    analyze_process "PopGenVCF" "VCFtools Population Filter"
    
    echo ""                                                                  >> \$OUTFILE
    echo "==================================================================" >> \$OUTFILE
    echo "Notes:"                                                            >> \$OUTFILE
    echo "  - Statistics include ALL completed tasks in this run"           >> \$OUTFILE
    echo "  - Times are wall-clock duration (start to finish)"              >> \$OUTFILE
    echo "  - Work directory: ${workflow.workDir}"                          >> \$OUTFILE
    echo "  - Generated: \$(date '+%Y-%m-%d %H:%M:%S')"                    >> \$OUTFILE
    echo "  - See pipeline_failures_summary.txt for failed/ignored samples" >> \$OUTFILE
    echo "==================================================================" >> \$OUTFILE
    
    echo "Pipeline execution statistics generated successfully"
    echo "Generated: pipeline_execution_stats.txt"
    echo "Generated: pipeline_execution_stats.tsv"
    echo "Generated: pipeline_failures_summary.txt"
    """
}
