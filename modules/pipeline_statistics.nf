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
    
    script:
    """
    #!/bin/bash
    set -e
    
    # Output files
    OUTFILE="pipeline_execution_stats.txt"
    TSV_FILE="pipeline_execution_stats.tsv"
    
    echo "==================================================================="  > \$OUTFILE
    echo "  Nextflow Pipeline - Process Completion Time Analysis"          >> \$OUTFILE
    echo "  Generated: \$(date '+%Y-%m-%d %H:%M:%S')"                      >> \$OUTFILE
    echo "==================================================================" >> \$OUTFILE
    echo ""                                                                  >> \$OUTFILE
    
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
                # Check if this is the right process type
                if grep -q "variant_calling:\$process_pattern" "\$dir/.command.run" 2>/dev/null; then
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
        done < <(find ${workflow.workDir} -maxdepth 2 -type d -name "[a-f0-9]*" 2>/dev/null)
        
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
    echo "==================================================================" >> \$OUTFILE
    
    echo "Pipeline execution statistics generated successfully"
    """
}
