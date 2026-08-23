# Optional Shelby Integration

Shelby is an optional state plane. Harness discovers callable Shelby MCP tools at
runtime; it does not infer availability from an installed plugin, configuration
file, or remembered session.

## When Shelby is available

Resolve one canonical project identifier and project ID for the current
repository or worktree before any memory read or write. If project scope is
ambiguous, resolve it before proceeding; do not search or write across projects
implicitly.

At session start, load the stable project brief. Use targeted live lookup for
changing facts, and search prior decisions before routing or architectural
choices. Capture only durable decisions and non-obvious findings in the resolved
project scope.

For substantial, multi-phase work where recovery or observability is useful:

1. create a plan,
2. log the Harness run and meaningful phase transitions,
3. save recovery checkpoints at useful boundaries, and
4. finish the run with its actual status.

Return available `project_id`, `run_id`, and checkpoint identifiers in the
Harness Result. Quick work need not manufacture plans or checkpoints solely to
populate those optional fields.

## When Shelby is unavailable

Continue with repository instructions, Git state, and repository-appropriate or
temporary local artifacts. Use temporary storage only for transient run state;
do not create a competing memory database. Preserve the same routing, authority,
verification, and result contracts, and do not widen permissions or silently
change route.

The missing Shelby is not blocking. State the missing enrichment only when it
materially affects continuity, and leave optional Shelby identifiers empty.
Never copy Shelby state, secrets, or run logs into repository files. A durable
fact belongs in repository documentation only when it is independently
appropriate project documentation.
