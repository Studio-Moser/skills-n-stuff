# Rubric migration

Read this from `harness:model-rubric` when an existing rubric lacks
`routing.orchestrator`, still carries a `cost` score, or still contains legacy
`routing.fallback`.

A rubric without `routing.orchestrator` requires an explicit orchestration
preference question; benchmark rank measures delegated coding work, not the
developer's trust for top-level judgment. Preserve capabilities, trust, taste,
billing semantics, every developer score and preference, and the scalar
`routing.<route>` primaries. Refresh benchmark evidence and replace `cost` with
`efficiency`. If capability reconciliation must change an unreachable primary,
complete and show that existing reconciliation before beginning fallback
migration; migration itself does not silently replace primaries. A previously
routed model remains eligible when reachable and trusted, but coding cost alone
never outranks the developer's stated orchestration preference.

Treat `routing.fallback` as legacy data only. During an explicit refresh, derive
the compatible route-specific replacements (see
[rubric-fallbacks.md](rubric-fallbacks.md)) while leaving the legacy value in
the temporary draft, validate every replacement chain, then remove
`routing.fallback` only after every replacement chain validates. Validate the
final draft again before writing it. Status checks never migrate a rubric, and a
failed migration leaves the original file unchanged.
