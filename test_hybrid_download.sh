#!/bin/bash
# Test script for hybrid download implementation

echo "==================================="
echo "Testing Hybrid Download Pipeline"
echo "==================================="
echo ""

# Create small test file with 3 accessions
echo "Creating test accession file..."
cat > test_hybrid_download.txt << 'EOF'
SRR3452754
SRR3452755
SRR3452756
EOF

echo "✓ Created test_hybrid_download.txt with 3 accessions"
echo ""

# Check if required tools are available
echo "Checking dependencies..."
command -v esearch >/dev/null 2>&1 && echo "✓ esearch available" || echo "✗ esearch missing"
command -v efetch >/dev/null 2>&1 && echo "✓ efetch available" || echo "✗ efetch missing"
command -v wget >/dev/null 2>&1 && echo "✓ wget available" || echo "✗ wget missing"
command -v prefetch >/dev/null 2>&1 && echo "✓ prefetch available" || echo "✗ prefetch missing"
command -v fasterq-dump >/dev/null 2>&1 && echo "✓ fasterq-dump available" || echo "✗ fasterq-dump missing"
command -v curl >/dev/null 2>&1 && echo "✓ curl available" || echo "✗ curl available"
echo ""

# Test ENA API connectivity
echo "Testing ENA API connectivity..."
test_srr="SRR3452754"
ena_response=$(curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=$test_srr&result=read_run&fields=fastq_ftp" | tail -n +2)

if [ -n "$ena_response" ]; then
    echo "✓ ENA API accessible"
    echo "  Sample response:"
    echo "  $ena_response" | head -c 100
    echo "..."
else
    echo "✗ ENA API not accessible or no data returned"
fi
echo ""

# Test NCBI connectivity
echo "Testing NCBI connectivity..."
if timeout 10 esearch -db sra -query "$test_srr" >/dev/null 2>&1; then
    echo "✓ NCBI accessible"
else
    echo "✗ NCBI not accessible or timeout"
fi
echo ""

echo "==================================="
echo "Ready to Run Test Pipeline"
echo "==================================="
echo ""
echo "Run the following command to test:"
echo ""
echo "nextflow run main.nf -profile local \\"
echo "  --reference IPO323.fasta \\"
echo "  --ploidy 1 \\"
echo "  --SRA_index test_hybrid_download.txt \\"
echo "  --outdir test_hybrid_output \\"
echo "  --NCBI_API_key \$NCBI_API_KEY"
echo ""
echo "Expected results:"
echo "  - 3 accessions processed"
echo "  - NCBI_download_urls.tsv with ENA URLs"
echo "  - Mix of ENA and/or NCBI downloads"
echo "  - Check logs for 'Successfully downloaded from ENA' vs 'NCBI'"
echo ""
echo "Monitor progress:"
echo "  tail -f .nextflow.log | grep -E 'ENA|NCBI|Successfully'"
echo ""
