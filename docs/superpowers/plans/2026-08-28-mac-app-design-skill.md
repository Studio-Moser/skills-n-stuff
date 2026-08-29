# Mac App Design Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SwiftUI-oriented Mac design skill with a focused skill that designs native-feeling macOS apps for Studio Moser's Tauri 2, SvelteKit 5, and Rust desktop stack.

**Architecture:** Keep a short `SKILL.md` as the decision and workflow entrypoint. Put detailed Mac interface, shell/bridge, prompting, and verification contracts in focused references so agents load only what their task needs.

**Tech Stack:** Agent Skills markdown, Claude Code plugin metadata, Tauri 2, SvelteKit 5, Rust, macOS WebView.

**Spec:** `docs/superpowers/plans/2026-08-28-mac-app-design-skill.md#global-constraints`

## Global Constraints

- Rename the skill to `mac-app-design`; do not preserve the old SwiftUI-first contract.
- Target macOS only. Other operating systems will receive separate skills.
- Treat Tauri 2 + SvelteKit 5 + Rust as the default implementation shape.
- Keep Swift limited to narrow Apple-only capability shims; do not teach SwiftUI as the UI path.
- Use Glaze only as clean-room observational evidence. Do not claim access to or copy private prompts, source, or assets.
- Preserve Mac-native behavior: system window, menu/shortcut model, compact metrics, resizable panes, keyboard and accessibility states, and restrained materials.
- Require browser-fixture iteration plus proof in the packaged/native shell for native seams.

---

### Task 1: Establish the prompt contract

**Files:**
- Rename: `plugins/mac-design/skills/mac-native-liquid-glass/` to `plugins/mac-design/skills/mac-app-design/`
- Modify: `plugins/mac-design/skills/mac-app-design/SKILL.md`
- Create: focused files under `plugins/mac-design/skills/mac-app-design/references/`

**Interfaces:**
- Consumes: the Shelby desktop boundary and the observed Glaze interaction patterns.
- Produces: a discoverable skill that directs agents through brief, architecture, native-shell, UI-kit, state, and verification decisions.

- [ ] Confirm the existing no-skill pressure scenarios omit a unified shell/content/bridge/state contract.
- [ ] Rename the skill directory and rewrite the entrypoint with the minimum routing guidance.
- [ ] Add focused references for architecture, interface kit, prompt contract, and verification.
- [ ] Validate the new skill structure.

### Task 2: Update plugin integration

**Files:**
- Modify: `plugins/mac-design/README.md`
- Modify: `plugins/mac-design/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `plugins/design-critic-loop/skills/design-critic-loop/SKILL.md`
- Modify: `plugins/design-critic-loop/skills/design-critic-loop/references/critic-prompts.md`

**Interfaces:**
- Consumes: the new skill name and rubric section names.
- Produces: consistent plugin discovery, installation metadata, and design-critic references.

- [ ] Update all old skill-name and rubric references.
- [ ] Release the breaking skill redesign as `0.2.0` in both version sources.
- [ ] Run the marketplace/version and skill-contract checks.

### Task 3: Behavioral verification

**Files:**
- Test only: isolated temporary directories outside the working tree.

**Interfaces:**
- Consumes: the finished skill and realistic Shelby-style requests.
- Produces: independent evidence that agents apply the architecture and Mac interface contracts.

- [ ] Forward-test a new Mac screen brief using the skill.
- [ ] Forward-test a critique of a web-dashboard-like Mac screen using the skill.
- [ ] Correct only failures demonstrated by those tests.
- [ ] Run the repository suite and an independent diff review.
