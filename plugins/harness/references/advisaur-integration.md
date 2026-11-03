# Optional Advisaur Integration

Advisaur is an optional state plane. Harness discovers callable Advisaur MCP tools at
runtime; it does not infer availability from an installed plugin, configuration
file, or remembered session.

## When Advisaur is available

Resolve one canonical project identifier and project ID for the current
repository or worktree before any memory read or write. If project scope is
ambiguous, resolve it before proceeding; do not search or write across projects
implicitly.

At session start, load the stable project brief. Use targeted live lookup for
changing facts, and search prior decisions before routing or architectural
choices. Capture only durable decisions and non-obvious findings in the resolved
project scope.

Consumers express optional domain memory behavior only through
`context.memory`. Harness translates each recall intent after resolving the
canonical project; consumers never discover or call Advisaur tools. A capture
intent runs only after the accepting workflow has reproduced proof and the
Harness Result has `evidence.outcome: proven`. Never persist a worker claim,
failed attempt, unproven draft, secret, or unbounded log.

For substantial, multi-phase work where recovery or observability is useful:

1. create a plan,
2. log the Harness run and meaningful phase transitions,
3. save recovery checkpoints at useful boundaries, and
4. finish the run with its actual status.

Keep `project_id`, `run_id`, and checkpoint identifiers with the Advisaur work;
they are not Harness Result fields. Quick work need not manufacture plans or
checkpoints.

## When Advisaur is unavailable

Continue with repository instructions, Git state, and repository-appropriate or
temporary local artifacts. Use temporary storage only for transient run state;
do not create a competing memory database. Preserve the same routing, authority,
verification, and result contracts, and do not widen permissions or silently
change route.

The missing Advisaur does not block execution. State the missing enrichment only when it
materially affects continuity.
Never copy Advisaur state, secrets, or run logs into repository files. A durable
fact belongs in repository documentation only when it is independently
appropriate project documentation.
