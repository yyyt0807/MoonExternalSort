# Keep the planning core portable and storage effects native

The ordering, run construction, merge planning, record codec, and manifest model
remain portable across MoonBit targets. Filesystem operations live behind a
Native adapter so core behavior can be tested deterministically without making
the public library depend on one host filesystem.
