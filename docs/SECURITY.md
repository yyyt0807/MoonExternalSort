# Security and resource boundaries

Treat input files, JSONL records, Run files and manifests as untrusted unless the caller controls the recovery directory.

The input line framer enforces `max_record_bytes` before building an unbounded line. Integer keys reject overflow. Manifest counters and budgets are validated. Run records require typed JSON fields and non-negative input positions. Merge output count must equal the committed descriptor counts before publication.

The v0.1 manifest is a crash-recovery contract, not an authenticity boundary. It does not yet contain cryptographic digests. An attacker able to modify the work directory may change valid Run contents while preserving counts. Protect the directory using host permissions and do not resume manifests from untrusted sources.

The memory budget covers retained-record estimates during Run generation, not
total process RSS. Merge-head retention is bounded independently by
`max_open_runs` and `max_record_bytes`; text keys have a conservative data
ceiling of `max_open_runs * (2 * max_record_bytes + 32)`. JSON decoding,
MoonBit runtime data, heap containers, OS buffers, paths and fixed I/O buffers
add overhead. Disk consumption is proportional to input size and may
temporarily include one predecessor and one successor generation.

The CLI never executes record content. It accepts only built-in key selectors and does not evaluate user scripts. Output replacement requires `--force`; a new job refuses an existing work directory to avoid trusting stale state.

Report vulnerabilities privately to the repository owner before public disclosure when practical.
