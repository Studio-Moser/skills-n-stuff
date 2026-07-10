# studio-baseline

Canonical, **public, fetchable** baseline that every Studio Moser repo shares — so house rules and personal model-routing reach every developer, whether or not they have the `pm` plugin installed.

- `House_Rules.md` — the one set of conventions (the `pm:house-rules` skill defers here).
- `Rubric_Setup.md` — how any agent helps a dev create their user-global model rubric, no plugin needed.
- `AGENTS_Baseline.md` — the managed block `/pm:setup` stamps into a repo's `AGENTS.md` (between `<!-- studio-baseline:start -->` / `<!-- studio-baseline:end -->`).

**Delivery model:** a PM runs `/pm:setup` once per repo to stamp the block (committed). Every dev then inherits it via clone; their agent reads `AGENTS.md` and, if their rubric isn't set, fetches `Rubric_Setup.md` and walks them through it. The plugin authors and refreshes; everyone consumes via git + these raw URLs.

Raw URL base: `https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/`
