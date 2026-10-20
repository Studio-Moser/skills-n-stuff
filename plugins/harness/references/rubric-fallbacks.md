# Rubric fallback chains

Read this from `harness:model-rubric` when deriving `fallbacks.<route>` chains
during an explicit rubric creation or refresh.

After choosing each primary, derive an ordered `fallbacks.<route>` chain from the
remaining rows. For every configured route:

- Filter other-provider rows by the same trust, latency, batch, computer-use,
  taste, independence, and operation constraints used to choose that route's
  primary. Preserve the developer's preference order among the compatible rows.
- The primary provider is first, and every fallback provider differs from every
  earlier provider in its chain. Include at most one row from each provider.
- A `taste` fallback meets `routing.taste_min`. An `independent` fallback remains
  distinct from every named authoring provider as well as every earlier provider
  in its chain.
- A matching native provider is reachable natively even if its row declares
  `via`; a non-native row is reachable only through its callable declared
  executor.
- Empty chains are allowed. Provider diversity is an optimization, so
  single-provider rubrics remain valid with no fallback chains.

Derive chains only from the developer's compatible rows, not from generic rubric
fields or raw executor errors, because a chain is standing authorization to
switch providers. For the same reason, legacy `routing.fallback` is never
automatic authorization. Only an explicit creation or refresh may derive
route-specific chains, and consumers use only the validated `fallbacks.<route>`
list as standing fallback authorization.
