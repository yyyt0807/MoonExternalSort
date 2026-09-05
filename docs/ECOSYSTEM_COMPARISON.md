# Ecosystem comparison

Snapshot date: 2026-09-05. Registry commit examined: `dc03c5f3aef329d650475f6d608228c632fc90c7`.

The mooncakes.io module index was searched across module names, descriptions and keywords for `external sort`, `external merge`, `out-of-core sort`, `spill sort`, `replacement selection`, and `k-way merge`. No module advertised external sorting as its core task. GitHub repository search with `language:MoonBit` also returned no external-merge-sort implementation.

The closest general result was `rabbyte/suffix-array`, which performs suffix sorting for text indexing, not bounded-memory stable record sorting. Database, DataFrame and stream-processing packages may internally sort data, but do not expose this project's job contract: explicit retained-record budget, immutable Runs, bounded merge fan-in, recoverable Job Manifest, and atomic payload publication.

Rejected nearby project ideas are documented in [the workspace research report](../../docs/research/2026-09-05-new-project-collision-review.md). In particular, `mizchi/bit_pack` already implements Git packfile handling, while `cn-xjr/moongeokit` already advertises spatial indexing.

Search metadata can be incomplete. Re-run the comparison before proposal submission and before publishing to mooncakes.io, then inspect README and source for every newly discovered near neighbor.
