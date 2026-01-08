process PipelineStatistics {
    tag "Generating pipeline execution statistics"
    memory '8GB'
    cpus 1
    
    publishDir params.outdir, mode: 'copy'
    
    // Disable cleanup for this process to preserve work directories for analysis
    scratch false
    
    input:
    val ready
    val workdir_path
    
    output:
    path "pipeline_execution_stats.txt"
    path "pipeline_execution_stats.tsv"
    
    shell:
    '''
    #!/bin/bash
    
    OUTFILE="pipeline_execution_stats.txt"
    TSV_FILE="pipeline_execution_stats.tsv"
    WORKDIR="!{workdir_path}"
    
    echo "=================================================================" > $OUTFILE
    echo "  Nextflow Pipeline - Process Statistics" >> $OUTFILE
    echo "  Generated: $(date)" >> $OUTFILE
    echo "=================================================================" >> $OUTFILE
    echo "" >> $OUTFILE
    
    echo -e "Process\\tCount\\tAvg_Seconds\\tMin_Seconds\\tMax_Seconds" > $TSV_FILE
    
    # Function to get stats for a process
    get_stats() {
        local pattern=$1
        local name=$2
        
        times=""
        count=0
        
        for dir in $(find $WORKDIR -maxdepth 3 -type d -name "[a-f0-9]*" 2>/dev/null); do
            if [ -f "$dir/.command.run" ] && [ -f "$dir/.command.begin" ] && [ -f "$dir/.exitcode" ]; then
                # Match pattern in the process name line (e.g., "variant_calling:bwaMap")
                if grep "^### name:.*$pattern" "$dir/.command.run" 2>/dev/null | grep -q .; then
                    exitcode=$(cat "$dir/.exitcode")
                    if [ "$exitcode" -eq 0 ]; then
                        begin=$(stat -c %Y "$dir/.command.begin" 2>/dev/null)
                        end=$(stat -c %Y "$dir/.exitcode" 2>/dev/null)
                        if [ -n "$begin" ] && [ -n "$end" ]; then
                            duration=$((end - begin))
                            if [ $duration -gt 0 ] && [ $duration -lt 86400 ]; then
                                times="$times $duration"
                                count=$((count + 1))
                            fi
                        fi
                    fi
                fi
            fi
        done
        
        if [ $count -gt 0 ]; then
            sum=0
            min=999999
            max=0
            for t in $times; do
                sum=$((sum + t))
                [ $t -lt $min ] && min=$t
                [ $t -gt $max ] && max=$t
            done
            avg=$((sum / count))
            
            avg_m=$((avg / 60))
            avg_s=$((avg % 60))
            min_m=$((min / 60))
            min_s=$((min % 60))
            max_m=$((max / 60))
            max_s=$((max % 60))
            
            printf "%-30s Count: %4d   Avg: %2dm%02ds   Range: %dm%ds - %dm%ds\\n" \\
                "$name" "$count" "$avg_m" "$avg_s" "$min_m" "$min_s" "$max_m" "$max_s" >> $OUTFILE
            
            echo -e "$name\\t$count\\t$avg\\t$min\\t$max" >> $TSV_FILE
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
    echo "  - Times are wall-clock duration (start to finish)" >> $OUTFILE
    echo "  - Work directory: $WORKDIR" >> $OUTFILE
    echo "=================================================================" >> $OUTFILE
    
    echo "Statistics generated successfully"
    '''
}
