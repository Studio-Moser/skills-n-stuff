# Glaze Harness Contract

Static inspection of Glaze exposed enough of its harness to reproduce the useful
shape. Adapt this shape to the repository's existing commands and Tauri/Svelte/Rust
stack; do not copy Glaze-owned code or claim access to its private prompt.

## What the installed harness actually does

Glaze projects receive:

- managed `AGENTS.md` and `CLAUDE.md` bootstraps that point every agent at one
  centrally synchronized instruction file;
- a generated runtime-context document naming editable sources, runtime output,
  app bundle, bundle identifier, logs, SDK root, API index, component docs, and
  project skills;
- centrally projected skills/rules with compatibility aliases for multiple agent
  runtimes;
- a pinned project manifest and managed Node runtime instead of relying on the
  agent's ambient machine setup;
- separate renderer and backend builds;
- one command surface for `dev`, renderer-only development, format, lint,
  type-check, build, JSON verification, launch, bundle metadata refresh, and full
  repackaging;
- SDK migrations that keep generated apps aligned as native primitives, preload,
  permissions, component names, sizing, scrollbars, and packaging evolve;
- structured launch/package requests with UUID request IDs, a trusted result
  directory, explicit acceptance, bounded waits, and machine-readable results.

The key is not a magic prose prompt. The agent works inside a constrained,
self-describing product system and gets fast, deterministic feedback.

## Studio Moser equivalent

Every Mac app should make these seams obvious to an agent:

| Need | Project contract |
| --- | --- |
| Core instructions | `AGENTS.md`/`CLAUDE.md` points to the Mac design skill plus project-specific architecture rules |
| Runtime context | README or generated context names source roots, Tauri commands, data/log locations, capabilities, native shims, and package output |
| Fast renderer loop | one browser-fixture command using the exact production Svelte tree |
| Native loop | one Tauri development command against the same renderer |
| Inner checks | focused component tests, type checks, and Rust tests |
| Full gate | one command that runs tests, checks, production build, and browser end-to-end coverage |
| Mac package | one repository command that assembles the complete `.app`, including native extensions |
| Machine-readable result | stable exit status and parseable output for commands agents must orchestrate |

For Shelby App, the observed equivalents are `npm run dev`, `npm run tauri dev`,
focused Vitest/Rust checks, `npm run gate`, and `npm run build:mac`. Use the actual
repository commands when they differ.

## Agent workflow

1. Read the project instructions and runtime context before editing.
2. Inspect the current semantic components, tokens, capability adapter, and fixture
   runtime. Reuse them before adding anything.
3. Run the smallest baseline check that covers the surface being changed.
4. State the design contract from `Prompt Contract.md`.
5. Build the smallest complete vertical slice in the production render tree.
6. Exercise all relevant states with deterministic browser fixtures.
7. Check native-only behavior in the Tauri window.
8. Run focused tests, then the full gate.
9. Rebuild the packaged `.app` when bundle resources, capabilities, signing,
   entitlements, extensions, or native shims changed.
10. Report exact checks, results, and unproven seams.

## UI-kit discipline

Glaze's renderer does not ask each generated app to rediscover Mac controls. Its
SDK exposes semantic components and central CSS, while migrations move apps toward
new native-backed defaults. Use the same discipline:

- keep shared shell, toolbar, sidebar, splitter, inspector, fields, menus,
  popovers, dialogs, lists, empty states, type roles, and semantic tokens in one
  small product UI kit;
- let context select size and treatment instead of passing arbitrary style props;
- include a browser-rendered component gallery that shows every supported state,
  density, appearance, and accessibility variant;
- make product screens consume the kit; do not hand-style near-duplicates;
- when a platform behavior improves, migrate the shared primitive and its callers
  together rather than layering compatibility CSS forever.

## Guardrails

- Do not overwrite project-authored instructions when refreshing managed content.
- Do not let a renderer command grant broader system access than its name implies.
- Do not treat a successful production web build as a successful Mac package.
- Do not launch or package through brittle UI automation when a repository command
  can return an explicit result.
- Do not add a migration framework until more than one shipped app needs automated
  UI-kit upgrades; keep the current shared skill and component package authoritative
  until then.
