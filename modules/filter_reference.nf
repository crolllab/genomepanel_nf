process filterReference {
    
    publishDir "${params.outdir}/reference", mode: 'copy'
    
    input:
    path reference
    val min_length
    
    output:
    path "*.red.fasta", emit: filtered_fasta
    path "*.stats.txt", emit: stats
    
    script:
    def base_name = reference.baseName
    """
    #!/usr/bin/env python3
    
    import sys
    
    min_length = ${min_length}
    input_fasta = "${reference}"
    output_fasta = "${base_name}.red.fasta"
    stats_file = "${base_name}.filter_stats.txt"
    
    # Simple FASTA parser and filter
    kept_contigs = []
    removed_contigs = []
    
    current_header = None
    current_seq = []
    
    def process_sequence(header, seq_list):
        \"\"\"Process a single sequence entry\"\"\"
        seq = ''.join(seq_list)
        seq_len = len(seq)
        contig_id = header.split()[0] if header else "unknown"
        
        if seq_len >= min_length:
            kept_contigs.append((contig_id, seq_len))
            return (header, seq)
        else:
            removed_contigs.append((contig_id, seq_len))
            return None
    
    # Read and filter FASTA
    with open(input_fasta, 'r') as in_handle, open(output_fasta, 'w') as out_handle:
        for line in in_handle:
            line = line.rstrip()
            if line.startswith('>'):
                # Process previous sequence if any
                if current_header is not None:
                    result = process_sequence(current_header, current_seq)
                    if result:
                        header, seq = result
                        out_handle.write(f"{header}\\n")
                        # Write sequence in 80 character lines
                        for i in range(0, len(seq), 80):
                            out_handle.write(seq[i:i+80] + "\\n")
                
                # Start new sequence
                current_header = line
                current_seq = []
            else:
                current_seq.append(line)
        
        # Process last sequence
        if current_header is not None:
            result = process_sequence(current_header, current_seq)
            if result:
                header, seq = result
                out_handle.write(f"{header}\\n")
                for i in range(0, len(seq), 80):
                    out_handle.write(seq[i:i+80] + "\\n")
    
    # Write statistics
    with open(stats_file, 'w') as stats:
        stats.write(f"Reference filtering statistics\\n")
        stats.write(f"Minimum contig length: {min_length} bp\\n")
        stats.write(f"\\nKept contigs: {len(kept_contigs)}\\n")
        stats.write(f"Removed contigs: {len(removed_contigs)}\\n")
        stats.write(f"\\nRemoved contig details:\\n")
        for contig_id, length in removed_contigs:
            stats.write(f"  {contig_id}: {length} bp\\n")
        
        if len(kept_contigs) == 0:
            stats.write("\\nWARNING: No contigs passed the filter!\\n")
            sys.exit(1)
    
    print(f"Filtered reference: kept {len(kept_contigs)} contigs, removed {len(removed_contigs)} contigs")
    """
}
