# Independent Product Pulse and PM Setup Design

## Goal

Configure Product Pulse and PM independently for `skills-n-stuff` and `agents` so each repository owns its research context, reports, GitHub pull requests, issue lifecycle, and auto-merge behavior.

## Repository Boundaries

### skills-n-stuff

`skills-n-stuff` is the public Studio Moser plugin and skill collection. Its Product Pulse project will research AI-agent tooling, plugin and skill ecosystems, product-research workflows, distribution, interoperability, and relevant technical changes.

Its research files will live in `docs/research/`. Its `pulse-config.yaml` will contain only the `skills-n-stuff` repository, use `main`, enable auto-merge, and use Shelby memory.

### agents

`agents` is Tim Moser's private, per-developer agent-configuration repository. Its Product Pulse project will research cross-tool agent configuration, portable instructions and skills, configuration security, machine synchronization, and operational reliability.

Its research files will live in `docs/research/`. Its `pulse-config.yaml` will contain only the `agents` repository, use `main`, enable auto-merge, and use Shelby memory.

## Generated Files

Each repository will independently contain:

- `docs/research/pulse-config.yaml`
- `docs/research/research-context.md`
- `docs/research/research-sources.yaml`
- `docs/research/deep-dives/`
- `.pm/config.yml`
- `.pm/state.yml`
- `.pm/out-of-scope/README.md`
- `CONTEXT.md`
- `docs/adr/0000-template.md`
- `planning/` backlog and workflow files

The context and sources will be derived from the repository's current README and verified authoritative web sources. Both projects will be recorded as mature, per the approved setup design.

## PM Configuration

Each repository will use GitHub Issues in its own `Studio-Moser` repository as the PM backend. Setup will provision the standard PM label taxonomy in both repositories and use label-only mode without a GitHub Projects v2 board. Each project will use a 30-day stale threshold, ADRs, an initially empty domain glossary, and its local `docs/research/` directory as the research-ingestion source.

The Product Pulse configuration in each repository will include local `planning/todos.md` and `planning/ideas.md` backlog paths shared with PM.

## GitHub Delivery

Product Pulse skills will create a branch and pull request in the repository whose configuration they discover. `auto_merge: true` will queue a squash merge when repository protections permit it. A blocked merge remains available for human review instead of bypassing GitHub controls.

## Isolation Rules

- Neither `pulse-config.yaml` references the other repository.
- Neither `.pm/config.yml` targets the other repository.
- Reports from one project are never saved in the other project's research directory.
- Each project uses a distinct project ID and memory tag: `skills-n-stuff` and `agents`.
- The `agents` configuration contains no literal `/Users/<name>` path.

## Verification

Setup is complete when both Product Pulse and PM configurations validate successfully, reference only their local repository, use the real default branch, enable GitHub auto-merge, have the standard GitHub labels provisioned, and all generated files are tracked by Git rather than ignored.
