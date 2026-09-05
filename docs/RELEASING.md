# Releasing

1. Re-run the mooncakes.io and public-repository collision search.
2. Insert the newly approved public repository URL in `moon.mod`; update
   `CHANGELOG.md`, the ecosystem snapshot and version.
3. Run `moon update`, strict check/test, format and interface generation.
4. Run both README examples on Windows and one Unix platform.
5. Review generated interfaces and `moon publish --dry-run` output.
6. Tag only after CI succeeds on Linux, macOS and Windows.
7. Publish to mooncakes.io and verify the package page and install command.

Repository creation, remote configuration, commits, tags, pushes and package
publication require an explicit maintainer command. The initial local project
intentionally has no Git repository or remote configured.

Do not publish generated build output, recovery workspaces or benchmark datasets with unclear redistribution rights.
