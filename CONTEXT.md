# MoonExternalSort

MoonExternalSort defines the domain language for stably ordering record streams
that may exceed memory while keeping resource use, intermediate state, and
publication outcomes explicit.

## Language

**Input Record**:
One caller-supplied payload together with the Sort Key derived from it and its
monotonic Input Position.
_Avoid_: Row, line, item

**Sort Key**:
The text or signed-integer value used to order Input Records.
_Avoid_: Index, ID, field

**Input Position**:
The monotonic ordinal assigned when an Input Record enters a Sort Job and used
to preserve stable ordering when Sort Keys compare equal.
_Avoid_: Sequence number, row number

**Sort Job**:
One declared transformation from an input record stream to a single ordered
output, including its ordering rules and Resource Budget.
_Avoid_: Process, task, batch

**Resource Budget**:
The explicit limits on retained record bytes, open Runs, record size, and
intermediate work that constrain a Sort Job.
_Avoid_: Memory hint, performance setting

**Run**:
An immutable, internally ordered sequence of Input Records materialized as an
intermediate result.
_Avoid_: Chunk, partition, temporary file

**Merge Group**:
A bounded ordered set of Runs consumed together to produce one successor Run.
_Avoid_: Batch, level, shard

**Merge Pass**:
The complete set of Merge Groups that transforms all Runs from one generation
into the next generation.
_Avoid_: Round, phase, iteration

**Job Manifest**:
A durable, versioned description of committed Runs and Merge Pass progress from
which an interrupted Sort Job can safely continue.
_Avoid_: Log, checkpoint file, cache

**Published Output**:
The sole final ordered stream made visible by an atomic publication step after
all required Runs have been merged and validated.
_Avoid_: Last Run, result file, destination

**Recovery**:
Continuation from the last valid Job Manifest without trusting uncommitted or
unverified intermediate artifacts.
_Avoid_: Replay, retry, resume flag
