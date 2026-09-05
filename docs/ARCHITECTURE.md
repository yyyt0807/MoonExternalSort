# Architecture

MoonExternalSort separates deterministic ordering from host effects.

```text
UTF-8 input chunks
  -> bounded LineFramer
  -> serializable KeySelector
  -> budgeted RunBuilder
  -> immutable Run files
  -> bounded Merge Groups / Merge Passes
  -> final Run
  -> payload-only staging output
  -> atomic Published Output
```

The root package owns typed keys, stable comparison, record accounting, Run construction, heap merging, merge planning, Run JSONL framing, and the Job Manifest schema. It contains no filesystem or wall-clock access and is checked on all MoonBit targets.

`adapter/native` owns file handles, temporary artifacts, atomic renames and JSONL/TSV key extraction. It reads input in 8 KiB chunks. The line framer retains at most one configured record; Run generation retains records only until the configured estimate is reached. A merge retains one decoded head per open Run plus bounded I/O buffers.

The manifest is committed only after every successor Run in a Merge Pass has been closed and renamed. After that commit, predecessor Runs may be removed. A crash before the commit leaves the previous manifest authoritative; a crash after it leaves the new manifest authoritative. Partial `.tmp` files are never referenced by a committed manifest.

The final payload stream follows the same protocol: complete and sync a staging file, close it, rename it to the requested output, then mark the manifest `published`.
