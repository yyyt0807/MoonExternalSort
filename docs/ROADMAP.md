# Roadmap

## v0.1

- Stable text and signed-integer keys.
- Whole-line, delimited-field and JSONL-field selectors.
- Bounded line framing and Run construction.
- Heap-based multi-pass merging under a file fan-in.
- Atomic manifests, resumable committed merge passes and atomic output.
- Quoted CSV selection and streaming sortedness verification.
- Stable bounded Top-K selection and deterministic resource estimation.
- Cross-target core tests and Native filesystem tests.

## Later, only with evidence of need

- Cryptographic Run digests and input identity binding.
- Replacement-selection Run generation.
- Loser-tree merge benchmark against the binary heap.
- Locale-independent decimal and timestamp key types.
- Explicit cancellation and cleanup commands.
- Streaming standard input for non-recoverable jobs.

MoonExternalSort will not become a database, query language, DataFrame or distributed execution engine.
