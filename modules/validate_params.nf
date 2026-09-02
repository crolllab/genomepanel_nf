// =============================================================================
//  Startup parameter validation and --help
// =============================================================================
//  Everything the user can get wrong on the command line is checked here,
//  before the workflow submits a single task.
//
//  Two failure modes motivated this module:
//
//    * raw tool errors  -- a mistyped --reference used to surface as a samtools
//      "No such file or directory" from inside a container, repeated over six
//      retries of three processes, dozens of lines away from the actual cause;
//
//    * silent success   -- a --reads glob matching nothing used to index the
//      reference and then exit 0, with no warning and no VCF.
//
//  So: every path and glob is resolved here (matching nothing is an error, not
//  a no-op), and checks accumulate into a list rather than aborting on the
//  first failure, so one launch reports every problem at once.
// =============================================================================


// ---------------------
// Parameter inventory
// ---------------------

// Parameters the pipeline accepts. Anything else is a typo.
def knownParams() {
    [
        'help',
        'outdir',
        'reference', 'reference_segments', 'min_contig_length', 'bwa_index',
        'reads', 'SRA_index', 'SRR_sample_map', 'NCBI_API_key', 'bam_input',
        'ploidy', 'call_invar_sites', 'use_duplicate_reads', 'genomicsdb_batch_size',
        'keep_bam', 'keep_gvcf',
        'plink_pca', 'plink_relationships', 'plink_ld_prune',
        'slurm_queue'
    ] as Set
}

// Nextflow's own options take a single dash. Passing them with two dashes
// creates a pipeline parameter that is silently ignored -- `--workdir /scratch`
// in particular looks like it works and then writes to ./work anyway.
def nextflowOptionAliases() {
    [
        'workdir'      : '-work-dir',
        'work_dir'     : '-work-dir',
        'work-dir'     : '-work-dir',
        'resume'       : '-resume',
        'profile'      : '-profile',
        'config'       : '-c / -config',
        'params_file'  : '-params-file',
        'params-file'  : '-params-file',
        'with_report'  : '-with-report',
        'with_trace'   : '-with-trace',
        'bg'           : '-bg',
        'version'      : '-version'
    ]
}

// Parameters that take a text value. Given as a bare flag (`--reads --ploidy 2`,
// easy to hit when a line continuation is dropped) Nextflow sets them to the
// boolean `true`, which used to blow up later as "Missing process or function
// tokenize([;])".
def stringParams() {
    ['reference', 'reads', 'SRA_index', 'bam_input', 'bwa_index',
     'SRR_sample_map', 'slurm_queue', 'outdir', 'NCBI_API_key']
}

// Parameters that are on/off switches.
def booleanParams() {
    ['keep_bam', 'keep_gvcf', 'call_invar_sites', 'use_duplicate_reads',
     'plink_pca', 'plink_relationships', 'plink_ld_prune']
}


// ---------------------
// Small helpers
// ---------------------

// Record one problem: a one-line title plus optional explanatory lines.
def addProblem(List store, String title, List detail = []) {
    store << [title: title, detail: detail]
    return store
}

// Several locations can be given to one parameter by joining the patterns with a
// semicolon. Semicolon rather than comma because a comma already means brace
// alternation inside a glob -- '*_{1,2}.fastq.gz' -- and splitting on it would
// tear every ordinary read pattern in half.
def patternSeparator() { return ';' }

// A representative quoted pattern for each glob-valued parameter, used in messages.
def exampleGlob(String name) {
    def examples = ['reads'    : "'path/to/reads/*_{1,2}.fastq.gz'",
                    'bam_input': "'path/to/bams/*.bam'"]
    return examples.get(name?.replaceAll(/^--/, ''), "'path/to/files/*'")
}

def splitPatterns(value) {
    return value.toString().tokenize(patternSeparator()).collect { pat -> pat.trim() }.findAll { pat -> pat }
}

// True if the string contains a comma that is not inside {...} alternation.
def hasCommaOutsideBraces(String s) {
    def depth = 0
    def found = false
    s.each { c ->
        if (c == '{') depth += 1
        else if (c == '}') depth -= 1
        else if (c == ',' && depth <= 0) found = true
    }
    return found
}

// When a pattern matches nothing, work out whether the user reached for the wrong
// separator. Only ever called on failure, so a genuine comma or pipe in a filename
// that does resolve is never second-guessed.
def separatorHint(String name, String value) {
    def example = "--${name} 'runA/*_{1,2}.fastq.gz${patternSeparator()}runB/*_{1,2}.fastq.gz'"

    if (value.contains('|'))
        return ["This looks like two or more patterns joined with '|'. Use a semicolon:",
                "  ${example}"]

    if (hasCommaOutsideBraces(value))
        return ["This looks like two or more patterns joined with ','. Commas are reserved for",
                "brace alternation inside a glob (the {1,2} in '*_{1,2}.fastq.gz'), so patterns",
                "are separated with a semicolon instead:",
                "  ${example}"]

    def words = value.trim().split(/\s+/)
    if (words.size() > 1 && words.findAll { w -> w.contains('/') || w.contains('*') }.size() > 1)
        return ["This looks like two or more patterns separated by spaces. Join them with a",
                "semicolon, inside one set of quotes:",
                "  ${example}"]

    return []
}

// Resolve a path or glob to the list of files it actually matches.
// Returns an empty list for a glob that matches nothing *and* for a plain path
// that does not exist, so callers can treat both the same way.
def globMatches(String pattern) {
    try {
        def resolved = file(pattern.trim())
        if (resolved instanceof List)
            return resolved
        return resolved.exists() ? [resolved] : []
    }
    catch (Exception _e) {
        return []
    }
}

def hasGlobChars(String s) {
    return (s =~ /[\*\?\[\]\{\}]/).find()
}

// Absolute path for display, so "no such file" messages show where we looked.
def displayPath(String p) {
    try { return file(p.trim()).toAbsolutePath().toString() }
    catch (Exception _e) { return p }
}

def humanBytes(long n) {
    if (n < 1024)             return "${n} B"
    if (n < 1024L * 1024)     return String.format("%.1f KB", n / 1024.0)
    if (n < 1024L * 1024 * 1024) return String.format("%.1f MB", n / (1024.0 * 1024))
    return String.format("%.1f GB", n / (1024.0 * 1024 * 1024))
}

// Strip the FASTQ extension and any trailing read-number token, so that
// SRR123_1.fastq.gz and SRR123_2.fastq.gz collapse to the same key.
// Used only to count pairs and spot leftovers for the startup summary --
// the actual pairing is still done by Channel.fromFilePairs.
def readPairKey(String filename) {
    def base = filename.replaceAll(/(?i)\.(fastq|fq)(\.gz)?$/, '')
    def m = (base =~ /^(.+)[._-](?:R|r)?([12])$/)
    return m.matches() ? m.group(1) : base
}

// Integer parameter check. Returns the parsed value, or null if unusable.
// `allowFalse` covers --min_contig_length, whose "off" value is the boolean false.
def checkInteger(String name, value, Map opts, List problems) {
    def required   = opts.required   ?: false
    def min        = opts.min        != null ? opts.min : 0
    def allowFalse = opts.allowFalse ?: false
    def purpose    = opts.purpose    ?: ''
    def example    = opts.example    ?: ''

    if (allowFalse && (value == false || value?.toString()?.toLowerCase() == 'false'))
        return null

    if (value == null || value.toString().trim().isEmpty()) {
        if (required)
            addProblem(problems, "--${name} is required but was not given", [purpose, example].findAll { d -> d })
        return null
    }

    if (value instanceof Boolean) {
        addProblem(problems, "--${name} was given without a value",
                   ["A number must follow the flag. Check for a missing value or a dropped line continuation (\\).",
                    example].findAll { d -> d })
        return null
    }

    def text = value.toString().trim()
    if (!(text ==~ /^-?\d+$/)) {
        addProblem(problems, "--${name} must be a whole number, but was '${text}'",
                   ["Give a plain number of base pairs -- suffixes such as kb, Mb or Gb are not understood.",
                    example].findAll { d -> d })
        return null
    }

    def parsed = text as Integer
    if (parsed < min) {
        addProblem(problems, "--${name} must be ${min} or greater, but was ${parsed}",
                   [purpose, example].findAll { d -> d })
        return null
    }
    return parsed
}

// Boolean parameter check. Guards against `--call_invar_sites yes`, which is a
// truthy string in Groovy but is compared against the literal "true" inside the
// process scripts -- so the flag would appear to be set and do nothing.
def checkBoolean(String name, value, List problems) {
    if (value instanceof Boolean) return
    def text = value?.toString()?.trim()?.toLowerCase()
    if (text in ['true', 'false']) return
    addProblem(problems, "--${name} must be true or false, but was '${value}'",
               ["Write the flag on its own to switch it on (--${name}), or give it an explicit value (--${name} true)."])
}

// Report on a reference FASTA that exists but cannot be used as-is.
def fastaProblems(reference) {
    def problems = []
    def name = reference.name.toLowerCase()

    if (name.endsWith('.gz') || name.endsWith('.bz2') || name.endsWith('.zip')) {
        problems << "The file is compressed. BWA, samtools and GATK all need an uncompressed FASTA here -- decompress it first (gunzip)."
        return problems
    }
    if (!(name ==~ /.*\.(fasta|fa|fna|fas|fsa|seq)$/))
        problems << "The extension is not a recognised FASTA extension (.fasta, .fa, .fna, .fas)."

    try {
        if (reference.size() == 0) {
            problems << "The file is empty (0 bytes)."
            return problems
        }
        def firstLine = null
        reference.withReader { r -> firstLine = r.readLine() }
        if (firstLine != null && !firstLine.startsWith('>'))
            problems << "The first line is not a FASTA header (it does not start with '>')."
    }
    catch (Exception e) {
        problems << "The file could not be read: ${e.message}"
    }
    return problems
}

// Nearest ancestor of `p` that exists, or null. Recursive because the Nextflow
// language parser no longer supports `while` loops.
def nearestExisting(p) {
    if (p == null) return null
    if (p.exists()) return p
    return nearestExisting(p.getParent())
}

// The output directory is only touched by publishDir, late in the run. Check it
// up front so a read-only path fails now rather than after the variant calling.
def outdirProblem(String outdir) {
    try {
        def target = file(outdir)
        if (target.exists() && !target.isDirectory())
            return "--outdir points at ${displayPath(outdir)}, which exists but is not a directory"

        def probe = nearestExisting(target)
        if (probe == null)
            return "--outdir ${displayPath(outdir)} cannot be resolved to a writable location"
        if (!java.nio.file.Files.isWritable(probe))
            return "--outdir ${displayPath(outdir)} is not writable (nearest existing directory: ${probe})"
        return null
    }
    catch (Exception e) {
        return "--outdir ${outdir} could not be checked: ${e.message}"
    }
}


// ---------------------
// Individual input checks
// ---------------------

// Returns the resolved reference Path, or null if it could not be used.
def checkReference(List problems, List _warnings, Map summary) {
    if (!params.reference) {
        addProblem(problems, "--reference is required but was not given",
                   ["The pipeline needs a reference genome in uncompressed FASTA format.",
                    "e.g.  --reference /data/genomes/my_genome.fasta"])
        return
    }
    if (params.reference instanceof Boolean) return   // already reported as a bare flag

    def pattern = params.reference.toString().trim()
    def matches = globMatches(pattern)

    if (matches.isEmpty()) {
        addProblem(problems, "--reference file not found: ${displayPath(pattern)}",
                   ["Nothing exists at that path. Check the spelling, and note that a relative",
                    "path is resolved against the directory you launched nextflow from."])
        return null
    }
    if (matches.size() > 1) {
        addProblem(problems, "--reference matched ${matches.size()} files, but exactly one is required",
                   ["Matched: ${matches.take(5).collect { m -> m.name }.join(', ')}${matches.size() > 5 ? ', ...' : ''}",
                    "Point --reference at a single FASTA file rather than a glob pattern."])
        return null
    }

    def reference = matches[0]
    def issues = fastaProblems(reference)
    if (issues) {
        addProblem(problems, "--reference ${reference.name} cannot be used as a reference genome", issues)
        return null
    }
    summary['Reference'] = "${reference.name} (${humanBytes(reference.size())})"
    return reference
}

// A --min_contig_length above every contig in the reference leaves filterReference
// with nothing to emit. Checking it here turns what was a Python traceback inside a
// container into a startup message. The scan stops at the first contig that clears
// the threshold, so the common (passing) case costs almost nothing and only the
// failing case reads the whole file -- which is exactly when the answer is wanted.
def checkMinContigLength(reference, List problems, List _warnings, Map _summary) {
    if (reference == null) return
    def raw = params.min_contig_length
    if (raw == null || raw == false || raw.toString().trim().toLowerCase() == 'false') return
    if (!(raw.toString().trim().isInteger())) return   // malformed: already reported

    def threshold = raw.toString().trim() as Integer
    def longest = 0
    def current = 0
    def kept    = 0
    def contigs = 0

    def SHORT_CIRCUIT = '__genomepanel_nf_contig_found__'
    try {
        reference.eachLine { line ->
            if (line.startsWith('>')) {
                if (contigs > 0) {
                    if (current > longest) longest = current
                    if (current >= threshold) kept += 1
                }
                contigs += 1
                current = 0
                if (kept > 0) throw new RuntimeException(SHORT_CIRCUIT)
            }
            else {
                current += line.trim().length()
            }
        }
        // Only reached when the file ended without any contig clearing the threshold.
        if (contigs > 0) {
            if (current > longest) longest = current
            if (current >= threshold) kept += 1
        }
    }
    catch (Exception e) {
        // Our own stop signal means a contig passed; anything else is a read failure,
        // which checkReference already reports.
        if (e.message != SHORT_CIRCUIT) return
    }

    if (kept == 0) {
        addProblem(problems, "--min_contig_length ${threshold} would remove every contig from the reference",
                   ["The longest contig in ${reference.name} is ${longest} bp, so nothing passes the filter.",
                    "Lower --min_contig_length, or drop it to use the reference unfiltered."])
    }
}

def checkReads(List problems, List warnings, Map summary) {
    if (!params.reads) return
    if (params.reads instanceof Boolean) return

    def raw = params.reads.toString()
    def patterns = splitPatterns(raw)
    if (patterns.isEmpty()) {
        addProblem(problems, "--reads was given an empty pattern")
        return
    }

    def allMatches = []
    def emptyPatterns = []
    patterns.each { pattern ->
        def matches = globMatches(pattern)
        if (matches.isEmpty()) emptyPatterns << pattern
        allMatches.addAll(matches)
    }

    if (allMatches.isEmpty()) {
        def detail = ["Looked for: ${patterns.collect { pat -> displayPath(pat) }.join('\n                 ')}",
                      "",
                      "The pipeline would otherwise index the reference and finish without calling",
                      "any variants, so this is treated as a fatal error.",
                      ""]

        def hint = separatorHint('reads', raw)
        if (hint) {
            detail.addAll(hint)
        }
        else {
            detail << "Common causes:"
            detail << "  * the pattern was not quoted, so the shell expanded it before Nextflow saw it"
            detail << "    -- always single-quote it: --reads 'data/*_{1,2}.fastq.gz'"
            detail << "  * the read-number token does not match the files, e.g. the pattern says"
            detail << "    {1,2} but the files are named _R1/_R2"
            detail << "  * a relative path resolved against the launch directory, not the script"
            if (!patterns.any { pat -> hasGlobChars(pat) })
                detail << "  * the pattern contains no wildcard at all, so it can only match one exact file"
        }
        addProblem(problems, "--reads matched no files", detail)
        return
    }

    if (emptyPatterns) {
        warnings << ("--reads: ${emptyPatterns.size()} of ${patterns.size()} patterns matched no files: " +
                     emptyPatterns.join(', '))
    }

    // Group by sample key to report pairs and, more usefully, leftovers.
    def grouped  = allMatches.unique { f -> f.toAbsolutePath().toString() }.groupBy { f -> readPairKey(f.name) }
    def pairs    = grouped.findAll { _k, v -> v.size() == 2 }
    def unpaired = grouped.findAll { _k, v -> v.size() == 1 }
    def crowded  = grouped.findAll { _k, v -> v.size() > 2 }

    if (pairs.isEmpty()) {
        def detail = ["Files found: ${allMatches.take(6).collect { f -> f.name }.join(', ')}${allMatches.size() > 6 ? ', ...' : ''}",
                      ""]
        if (allMatches.size() == 1 && !patterns.any { pat -> hasGlobChars(pat) }) {
            detail << "--reads was given one plain file path with no wildcard in it. If you meant to"
            detail << "pass a pattern, quote it so the shell hands it to Nextflow intact:"
            detail << "  --reads 'path/to/reads/*_{1,2}.fastq.gz'"
        }
        else {
            detail << "--reads accepts paired-end data only, and expects the two mates of a sample to"
            detail << "differ solely by a read-number token (_1/_2 or _R1/_R2) before the extension."
            detail << "Single-end data must be supplied through --SRA_index instead."
        }
        addProblem(problems, "--reads matched ${allMatches.size()} file(s) but could not form a single read pair", detail)
        return
    }

    if (unpaired) {
        warnings << ("--reads: ${unpaired.size()} file(s) have no mate and will be silently ignored: " +
                     unpaired.values().flatten().take(6).collect { f -> f.name }.join(', ') +
                     (unpaired.size() > 6 ? ', ...' : ''))
    }
    if (crowded) {
        warnings << ("--reads: ${crowded.size()} sample prefix(es) matched more than 2 files; " +
                     "Channel.fromFilePairs takes the first two of each: " +
                     crowded.keySet().take(6).join(', '))
    }

    def emptyFiles = allMatches.findAll { f -> f.size() == 0 }
    if (emptyFiles)
        warnings << ("--reads: ${emptyFiles.size()} matched file(s) are empty (0 bytes): " +
                     emptyFiles.take(4).collect { f -> f.name }.join(', '))

    summary['Local FASTQ'] = "${allMatches.size()} files -> ${pairs.size()} read pair${pairs.size() == 1 ? '' : 's'}" +
                             (patterns.size() > 1 ? " from ${patterns.size()} patterns" : "")
}

def checkSraIndex(List problems, List warnings, Map summary) {
    if (!params.SRA_index) return
    if (params.SRA_index instanceof Boolean) return

    def pattern = params.SRA_index.toString().trim()
    def matches = globMatches(pattern)

    if (matches.isEmpty()) {
        addProblem(problems, "--SRA_index file not found: ${displayPath(pattern)}",
                   ["--SRA_index takes a plain-text file listing one accession per line",
                    "(SRR, ERR, DRR, SRX, SRP, PRJNA ...), not an accession itself."])
        return
    }
    if (matches.size() > 1) {
        addProblem(problems, "--SRA_index matched ${matches.size()} files, but exactly one is required")
        return
    }

    def accessionFile = matches[0]
    def accessions
    try {
        accessions = accessionFile.readLines().collect { l -> l.trim() }.findAll { l -> l && !l.startsWith('#') }
    }
    catch (Exception e) {
        addProblem(problems, "--SRA_index file ${accessionFile.name} could not be read: ${e.message}")
        return
    }

    if (accessions.isEmpty()) {
        addProblem(problems, "--SRA_index file ${accessionFile.name} contains no accessions",
                   ["The file is empty or contains only blank lines. List one accession per line."])
        return
    }

    def malformed = accessions.findAll { a -> !(a ==~ /^[A-Za-z]{2,6}[0-9]{3,}$/) }
    if (malformed)
        warnings << ("--SRA_index: ${malformed.size()} line(s) do not look like SRA/ENA accessions and " +
                     "will probably resolve to nothing: " + malformed.take(4).join(', '))

    if (!params.NCBI_API_key)
        warnings << ("--SRA_index without --NCBI_API_key: NCBI throttles anonymous E-utilities requests to " +
                     "3/second, so metadata lookup for large accession lists is slow and prone to retries. " +
                     "A free key (https://account.ncbi.nlm.nih.gov/) raises this to 10/second.")

    summary['SRA accessions'] = "${accessions.size()} from ${accessionFile.name}"
}

def checkSampleMap(List problems, List _warnings, Map summary) {
    if (!params.SRR_sample_map) return
    if (params.SRR_sample_map instanceof Boolean) return

    def pattern = params.SRR_sample_map.toString().trim()
    def matches = globMatches(pattern)

    if (matches.isEmpty()) {
        addProblem(problems, "--SRR_sample_map file not found: ${displayPath(pattern)}",
                   ["Expected a CSV file with one 'Run_ID,Sample_Name' pair per line and no header."])
        return
    }

    def mapFile = matches[0]
    def lines
    try {
        lines = mapFile.readLines().collect { l -> l.trim() }.findAll { l -> l }
    }
    catch (Exception e) {
        addProblem(problems, "--SRR_sample_map file ${mapFile.name} could not be read: ${e.message}")
        return
    }

    if (lines.isEmpty()) {
        addProblem(problems, "--SRR_sample_map file ${mapFile.name} is empty",
                   ["Expected one 'Run_ID,Sample_Name' pair per line."])
        return
    }

    // A tab-separated file is looked up with a comma-anchored grep in addRG, so
    // every lookup misses and every sample silently keeps its run ID.
    if (lines.every { l -> !l.contains(',') } && lines.any { l -> l.contains('\t') }) {
        addProblem(problems, "--SRR_sample_map file ${mapFile.name} is tab-separated, but must be comma-separated",
                   ["Sample names are looked up by comma, so a TSV would match nothing and every",
                    "sample would silently keep its original run ID.",
                    "e.g.  SRR2589044,REL2181A"])
        return
    }

    def malformed = lines.findAll { l -> l.tokenize(',').findAll { f -> f.trim() }.size() < 2 }
    if (malformed) {
        addProblem(problems, "--SRR_sample_map file ${mapFile.name} has ${malformed.size()} malformed line(s)",
                   ["Each line needs two comma-separated fields: Run_ID,Sample_Name",
                    "First offending line: '${malformed[0]}'"])
        return
    }

    def sampleNames = lines.collect { l -> l.tokenize(',')[1].trim() }.unique()
    summary['Sample map'] = "${lines.size()} run IDs -> ${sampleNames.size()} sample names"
}

def checkBamInput(List problems, List warnings, Map summary) {
    if (!params.bam_input) return
    if (params.bam_input instanceof Boolean) return

    def raw = params.bam_input.toString()
    def patterns = splitPatterns(raw)
    if (patterns.isEmpty()) {
        addProblem(problems, "--bam_input was given an empty pattern")
        return
    }

    def matches = []
    def emptyPatterns = []
    patterns.each { pattern ->
        def found = globMatches(pattern)
        if (found.isEmpty()) emptyPatterns << pattern
        matches.addAll(found)
    }
    matches = matches.unique { f -> f.toAbsolutePath().toString() }

    if (matches.isEmpty()) {
        def detail = ["Looked for: ${patterns.collect { pat -> displayPath(pat) }.join('\n                 ')}",
                      "",
                      "The pipeline would otherwise index the reference and finish without calling",
                      "any variants, so this is treated as a fatal error.",
                      ""]
        def hint = separatorHint('bam_input', raw)
        if (hint) detail.addAll(hint)
        else      detail << "Remember to single-quote the pattern: --bam_input 'bams/*.bam'"
        addProblem(problems, "--bam_input matched no files", detail)
        return
    }

    if (emptyPatterns)
        warnings << ("--bam_input: ${emptyPatterns.size()} of ${patterns.size()} patterns matched no files: " +
                     emptyPatterns.join(', '))

    // Accept either BAM index convention: sample.bam.bai or sample.bai.
    def missingIndex = matches.findAll { bam ->
        !file("${bam}.bai").exists() && !file("${bam.parent}/${bam.baseName}.bai").exists()
    }
    if (missingIndex) {
        addProblem(problems, "${missingIndex.size()} of ${matches.size()} BAM file(s) have no index",
                   (["Every BAM needs a .bai alongside it (either <name>.bam.bai or <name>.bai)."] +
                    ["Index with:  samtools index <file.bam>", "Missing for:"] +
                    missingIndex.take(8).collect { f -> "  ${f.name}" } +
                    (missingIndex.size() > 8 ? ["  ... and ${missingIndex.size() - 8} more"] : [])))
        return
    }

    def emptyFiles = matches.findAll { f -> f.size() == 0 }
    if (emptyFiles)
        warnings << ("--bam_input: ${emptyFiles.size()} matched file(s) are empty (0 bytes): " +
                     emptyFiles.take(4).collect { f -> f.name }.join(', '))

    summary['BAM files'] = "${matches.size()} files (all indexed)" +
                           (patterns.size() > 1 ? " from ${patterns.size()} patterns" : "")
}

def checkBwaIndex(List problems, List _warnings, Map summary) {
    if (!params.bwa_index) return
    if (params.bwa_index instanceof Boolean) return

    def prefix     = params.bwa_index.toString().trim()
    def extensions = ['.amb', '.ann', '.bwt.2bit.64', '.pac', '.0123']
    def missing    = extensions.findAll { ext -> !file("${prefix}${ext}").exists() }

    if (missing) {
        def detail = ["Prefix used: ${displayPath(prefix)}",
                      "Missing:     ${missing.join(', ')}"]
        // The classic bwa (not bwa-mem2) index uses .bwt/.sa instead.
        if (file("${prefix}.bwt").exists() || file("${prefix}.sa").exists())
            detail << ("Found a .bwt/.sa index, which is from the original bwa. This pipeline uses " +
                       "bwa-mem2, whose index is not compatible -- rebuild with 'bwa-mem2 index', " +
                       "or drop --bwa_index and let the pipeline build it.")
        else
            detail << ("--bwa_index takes the path prefix the index was built with, not a directory " +
                       "and not one of the index files. Drop the flag to have the pipeline build the " +
                       "index itself.")
        addProblem(problems, "--bwa_index is incomplete: ${missing.size()} of ${extensions.size()} bwa-mem2 index files are missing", detail)
        return
    }
    summary['BWA index'] = "complete (5/5 files)"
}


// An unquoted glob is expanded by the shell before Nextflow ever sees it: the first
// path becomes the parameter value and the rest arrive as positional arguments, which
// Nextflow silently discards. That is the one mistake that can quietly process a
// single sample out of ninety, so the leftovers are turned into an error naming the
// parameter that swallowed them.
def checkStrayArguments(List problems, strayArgs) {
    def strays = (strayArgs ?: []) as List
    if (!strays) return

    // The parameter immediately before the strays on the command line is the culprit.
    def culprit = null
    try {
        def tokens = workflow.commandLine.tokenize(' ')
        def firstStray = tokens.indexOf(strays[0].toString())
        if (firstStray > 0)
            culprit = tokens.take(firstStray).reverse().find { tok -> tok.startsWith('--') }
    }
    catch (Exception _e) { /* best effort only */ }

    def existing = strays.findAll { s -> file(s.toString()).exists() }
    def detail = []

    if (culprit && existing.size() == strays.size()) {
        detail << "${strays.size() == 1 ? 'It is an existing file' : 'They are all existing files'}, so ${culprit} was almost certainly given an"
        detail << "unquoted glob pattern: the shell expanded it, ${culprit} received only the"
        detail << "first file, and the ${strays.size() == 1 ? 'remaining one was' : "remaining ${strays.size()} were"} dropped."
        detail << ""
        detail << "Put the pattern in single quotes so Nextflow expands it instead:"
        detail << "  ${culprit} ${exampleGlob(culprit)}"
    }
    else {
        detail << "Nextflow ignores positional arguments, so these had no effect."
        detail << "Every value must be attached to a parameter, and any glob pattern must be quoted."
    }

    detail << ""
    detail << "Ignored:"
    strays.take(5).each { s -> detail << "  ${s}" }
    if (strays.size() > 5) detail << "  ... and ${strays.size() - 5} more"

    addProblem(problems,
               strays.size() == 1 ? "1 argument was not attached to any parameter"
                                  : "${strays.size()} arguments were not attached to any parameter",
               detail)
}


// ---------------------
// Main entry point
// ---------------------

def validateParams(strayArgs = null) {

    def problems = []
    def warnings = []
    def summary  = [:]

    checkStrayArguments(problems, strayArgs)

    // --- unknown, misspelled and single-dash-option parameters ---------------
    def aliases = nextflowOptionAliases()
    def unknown = (params.keySet() as Set) - knownParams()

    def misusedOptions = unknown.findAll { u -> aliases.containsKey(u) }
    misusedOptions.each { name ->
        addProblem(problems, "--${name} is not a pipeline parameter; you probably meant '${aliases[name]}'",
                   ["Nextflow's own options take a single dash. Passed with two dashes they become",
                    "an unused pipeline parameter and have no effect at all."])
    }

    def realUnknown = unknown - misusedOptions
    if (realUnknown) {
        addProblem(problems, "Unknown parameter(s): ${realUnknown.sort().join(', ')}",
                   ["Valid parameters are:"] +
                   knownParams().sort().collect { k -> "  --${k}" } +
                   ["", "Run with --help for a description of each."])
    }

    // --- value-taking parameters given as bare flags --------------------------
    stringParams().each { name ->
        if (params[name] instanceof Boolean) {
            addProblem(problems, "--${name} was given without a value",
                       ["A value must follow the flag. This usually means a value was omitted or a",
                        "line continuation (\\) was dropped, so the next flag was read as the value."])
        }
    }

    // --- on/off switches ------------------------------------------------------
    booleanParams().each { name -> checkBoolean(name, params[name], problems) }

    // --- numeric parameters ---------------------------------------------------
    checkInteger('ploidy', params.ploidy,
                 [required: true, min: 1,
                  purpose: "GATK HaplotypeCaller needs the sample ploidy to call genotypes: 1 for haploid organisms (most fungi, bacteria), 2 for diploids, higher for pooled samples.",
                  example: "e.g.  --ploidy 2"], problems)

    def segments = checkInteger('reference_segments', params.reference_segments,
                 [min: 0,
                  purpose: "Size in base pairs of the genome segments used for parallel variant calling; 0 disables segmentation.",
                  example: "e.g.  --reference_segments 1000000"], problems)

    checkInteger('min_contig_length', params.min_contig_length,
                 [min: 1, allowFalse: true,
                  purpose: "Contigs shorter than this many base pairs are dropped from the reference; false disables filtering.",
                  example: "e.g.  --min_contig_length 10000"], problems)

    checkInteger('genomicsdb_batch_size', params.genomicsdb_batch_size,
                 [min: 1,
                  purpose: "Number of samples GenomicsDBImport loads per batch.",
                  example: "e.g.  --genomicsdb_batch_size 200"], problems)

    if (segments != null && segments > 0 && segments < 10000)
        warnings << ("--reference_segments ${segments} is very small: variant calling is split into one task " +
                     "per segment per sample, so this will create an enormous number of short tasks. " +
                     "Values around 1000000 (1 Mb) are typical.")

    // --- input selection ------------------------------------------------------
    if (!params.reads && !params.SRA_index && !params.bam_input) {
        addProblem(problems, "No input data was provided",
                   ["Supply at least one of:",
                    "  --reads      'path/to/*_{1,2}.fastq.gz'   local paired-end FASTQ files",
                    "  --SRA_index  accessions.txt               SRA/ENA accessions, one per line",
                    "  --bam_input  'path/to/*.bam'              pre-processed, indexed BAM files"])
    }
    if (params.bam_input && (params.reads || params.SRA_index)) {
        addProblem(problems, "--bam_input cannot be combined with --reads or --SRA_index",
                   ["--bam_input skips trimming, mapping and deduplication entirely, so it is either",
                    "BAM input or read input, not both."])
    }

    // --- files and globs ------------------------------------------------------
    def reference = checkReference(problems, warnings, summary)
    checkMinContigLength(reference, problems, warnings, summary)
    checkReads(problems, warnings, summary)
    checkSraIndex(problems, warnings, summary)
    checkSampleMap(problems, warnings, summary)
    checkBamInput(problems, warnings, summary)
    checkBwaIndex(problems, warnings, summary)

    // --- execution environment -------------------------------------------------
    if (workflow.profile.tokenize(',').contains('slurm') && !params.slurm_queue) {
        addProblem(problems, "--slurm_queue is required when using -profile slurm",
                   ["Give the name of the SLURM partition to submit to, e.g.  --slurm_queue long",
                    "The partition should allow a walltime of at least 7 days for large datasets.",
                    "Shorter limits (1-2 days) may still work for smaller genomes or low-depth",
                    "sequencing, but any job exceeding the limit will be killed by SLURM.",
                    "",
                    "List partitions and their limits with:  scontrol show partition | grep -E 'PartitionName|MaxTime'"])
    }

    def outdirIssue = outdirProblem(params.outdir.toString())
    if (outdirIssue)
        addProblem(problems, outdirIssue,
                   ["Results are copied here at the end of each step; an unwritable path would only",
                    "fail once there were results to publish."])

    // --- combinations that are valid but rarely intended -----------------------
    if (params.SRR_sample_map && !params.SRA_index && !params.reads)
        warnings << "--SRR_sample_map has no effect with --bam_input: sample names are taken from the read groups already in the BAM headers."

    if (params.NCBI_API_key && !params.SRA_index)
        warnings << "--NCBI_API_key has no effect without --SRA_index; it is only used for SRA metadata lookups."

    if (params.plink_relationships && params.ploidy?.toString() == '1')
        warnings << ("--plink_relationships with --ploidy 1: the KING estimator is scaled by heterozygote " +
                     "counts, which are zero in haploid data, so the .king matrix will be -inf off-diagonal. " +
                     "Use the .rel (GRM) matrix instead.")

    if (params.keep_gvcf && params.bam_input && !params.reference_segments)
        warnings << "--keep_gvcf with --bam_input: per-sample GVCFs are published directly, without a merge step."

    return [problems: problems, warnings: warnings, summary: summary]
}

// Render the accumulated problems as one numbered block.
def formatProblems(List problems) {
    def out = new StringBuilder()
    out << "\n"
    out << "  =============================================================================\n"
    out << "   genomepanel_nf cannot start: ${problems.size()} problem${problems.size() == 1 ? '' : 's'} with this run\n"
    out << "  =============================================================================\n"
    problems.eachWithIndex { p, i ->
        out << "\n  ${i + 1}) ${p.title}\n"
        p.detail.each { line -> out << (line ? "     ${line}\n" : "\n") }
    }
    out << "\n"
    out << "  No tasks were submitted. Correct the above and re-launch.\n"
    out << "  Run 'nextflow run main.nf --help' for the full list of parameters.\n"
    return out.toString()
}

def helpMessage() {
    return """
   =============================================
   || GENOMEPANEL_NF VARIANT CALLING WORKFLOW ||
   =============================================
   Version ${workflow.manifest.version}

   Usage:
     nextflow run main.nf --reference <fasta> --ploidy <n> [input] [options]

   The reference genome and the ploidy are always required, plus at least one
   source of input data.

   Input data (at least one required; --bam_input excludes the other two)
     --reads <glob>            Paired-end FASTQ files.
                               --reads 'data/*_{1,2}.fastq.gz'
     --SRA_index <file>        Plain-text file of SRA/ENA accessions, one per line.
     --bam_input <glob>        Pre-processed, coordinate-sorted, indexed BAM files
                               carrying @RG headers. Skips trimming and mapping.
                               --bam_input 'bams/*.bam'

   Quoting and multiple locations
     Always put a glob pattern in SINGLE quotes. Unquoted, the shell expands it
     before Nextflow sees it, the parameter keeps only the first file and the rest
     are silently discarded. Double quotes work too, but leave \$ and ` live, so
     single quotes are the safe habit.

     To read from several locations, give one quoted value and separate the
     patterns with a SEMICOLON -- a comma cannot be used, because it already means
     alternation inside a glob (the {1,2} in '*_{1,2}.fastq.gz'):

       --reads 'runA/*_{1,2}.fastq.gz;runB/*_{1,2}.fastq.gz'
       --bam_input 'batch1/*.bam;batch2/*.bam'

     --reference and --SRA_index each take exactly one file, not a pattern.

   Reference genome
     --reference <fasta>       Uncompressed reference FASTA.                [required]
     --reference_segments <bp> Segment size for parallel calling; 0 = whole
                               chromosomes.                                 [0]
     --min_contig_length <bp>  Drop contigs shorter than this; false = keep all. [false]
     --bwa_index <prefix>      Path prefix of a pre-built bwa-mem2 index.

   Genotyping
     --ploidy <n>              Sample ploidy: 1 haploid, 2 diploid.         [required]
     --call_invar_sites        Also emit invariant sites (much larger output). [false]
     --use_duplicate_reads     Keep duplicate-flagged reads when calling.     [false]

   SRA options
     --NCBI_API_key <key>      NCBI API key; raises the E-utilities rate limit
                               from 3 to 10 requests/second. Recommended with
                               --SRA_index.
     --SRR_sample_map <csv>    CSV of 'Run_ID,Sample_Name', no header. Merges
                               several runs into one sample and renames samples.

   Population genetics (run on the thinned, MAF-filtered VCF)
     --plink_pca               Principal component analysis.                 [false]
     --plink_relationships     GRM (.rel) and KING (.king) matrices.         [false]
     --plink_ld_prune          LD pruning plus the pruned VCF.               [false]

   Output
     --outdir <dir>            Directory for final results.          [./nf_output/]
     --keep_bam                Publish per-sample deduplicated BAMs.         [false]
     --keep_gvcf               Publish per-sample GVCFs.                     [false]

   Execution
     --slurm_queue <name>      SLURM partition. Required with -profile slurm.
     --genomicsdb_batch_size <n>  Samples per GenomicsDBImport batch.        [200]

   Nextflow options (note the single dash)
     -profile <local|local_highCPU|slurm>   Execution profile.
     -work-dir <dir>           Directory for intermediate files.
     -resume                   Resume from the last completed step.

   Example:
     nextflow run main.nf \\
       --reference genome.fasta \\
       --reads 'fastq/*_{1,2}.fastq.gz' \\
       --ploidy 2 \\
       --outdir results

   Documentation: https://crolllab.github.io/genomepanel_nf/
   """
}
