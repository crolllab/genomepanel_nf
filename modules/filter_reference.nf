process filterReference {
    errorStrategy 'retry'
    maxRetries 6

    publishDir "${params.outdir}/reference", mode: 'copy'
    
    input:
    path reference
    val min_length
    
    output:
    path "*.red.fasta", emit: filtered_fasta
    path "*.filter_stats.txt", emit: stats
    
    script:
    def base_name = reference.baseName
    """
    #!/usr/bin/env python3
    
    import sys
    
    min_length = ${min_length}
    input_fasta = "${reference}"
    output_fasta = "${base_name}.red.fasta"
    stats_file = "${base_name}.filter_stats.txt"
    
    # Pass 1: scan contig lengths without buffering sequences
    contig_lengths = {}
    current_id = None
    current_len = 0
    
    with open(input_fasta, 'r') as fh:
        for line in fh:
            line = line.rstrip()
            if line.startswith('>'):
                if current_id is not None:
                    contig_lengths[current_id] = current_len
                current_id = line.split()[0][1:]
                current_len = 0
            else:
                current_len += len(line)
        if current_id is not None:
            contig_lengths[current_id] = current_len
    
    kept_set = {cid for cid, length in contig_lengths.items() if length >= min_length}
    removed = {cid: length for cid, length in contig_lengths.items() if length < min_length}
    
    # Pass 2: stream-write kept contigs (no sequence buffering)
    with open(input_fasta, 'r') as in_handle, open(output_fasta, 'w') as out_handle:
        write_this = False
        for line in in_handle:
            line = line.rstrip()
            if line.startswith('>'):
                contig_id = line.split()[0][1:]
                write_this = contig_id in kept_set
                if write_this:
                    out_handle.write(line + "\\n")
            elif write_this:
                out_handle.write(line + "\\n")
    
    # Write statistics
    with open(stats_file, 'w') as stats:
        stats.write(f"Reference filtering statistics\\n")
        stats.write(f"Minimum contig length: {min_length} bp\\n")
        stats.write(f"\\nKept contigs: {len(kept_set)}\\n")
        stats.write(f"Removed contigs: {len(removed)}\\n")
        stats.write(f"\\nRemoved contig details:\\n")
        for contig_id, length in removed.items():
            stats.write(f"  {contig_id}: {length} bp\\n")
        
        if len(kept_set) == 0:
            stats.write("\\nWARNING: No contigs passed the filter!\\n")
            sys.exit(1)
    
    print(f"Filtered reference: kept {len(kept_set)} contigs, removed {len(removed)} contigs")
    """
}
