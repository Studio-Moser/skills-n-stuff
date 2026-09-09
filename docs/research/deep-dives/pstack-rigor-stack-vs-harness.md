---
title: "pstack vs Harness: Buy the Verification Lever, Not the Ceremony"
resources:
  - url: https://www.youtube.com/watch?v=lUhXa8GiXns
    type: video
    title: "Pstack Is Agent Overkill. Use It Anyway!"
    published: 2026-09-08
tags: [skills, plugins, verification, principles, agent-orchestration, portability, ci, transcribe]
related_reports: [evidence-gated-agent-completion, agent-native-harness-and-pm, model-harness-unbundling]
---

### Research Coverage

Expected 1 resource, 1 ecosystem sweep, 1 project audit. Accepted/proven 3, failed 0, blocked 0, abandoned 0, unproven 0.

Run in-pass rather than through delegated Harness branches. Naming the rule I followed, per CLAUDE.md rule 2: rule 4's "match ceremony to the task" — the transcript, the pstack source, and the repo audit were bounded reads I already held context for, and delegation would have cost a context handoff without adding evidence. No branch manifest is reported because no branches were dispatched; every claim below is backed by a command I ran in this session.

One caveat on the primary source: the video has **no manual captions**, only auto-generated ones. Proper nouns are garbled throughout ("Pstack"/"potato mode"/"Laran"/"onslaught"/"brawl"). Every name in this report was re-derived from `github.com/cursor/plugins`, not from the transcript.

### Resource Summary

**"Pstack Is Agent Overkill. Use It Anyway!"** — Rob Shocks, published 2026-09-08 (today), 12:57. Fresh; no staleness concern.

A walkthrough of **pstack**, Lauren Tan's (`@poteto`) official Cursor plugin. Tan is ex-Netflix, React core team, and worked at SpaceX and Cursor. The video's framing is honest about the tradeoff its title concedes: pstack burns substantially more tokens and time in exchange for a much more hardened result, and the presenter says outright you shouldn't throw it at small front-end changes.

Verified structure (from `gh api repos/cursor/plugins/contents/pstack/skills`, 2026-09-08): **46 skill directories** — 25 workflow skills plus **21 `principle-*` leaf skills** — plus 2 subagents (`poteto-agent`, `comment-sicko`), a docs guide, and an automations pack. The router is `/poteto-mode`.

Transcript claims worth carrying forward:

- **Verification is the spine.** "Having a compile and go green on tests is not the same as actually testing and proving it works in terms of real artifact."
- **The `create-verification-skill` skill generates a scripted way to prove app behavior** — the presenter's stated favourite.
- **`show-me-your-work` caught the agent's own hallucinations**: "It caught three false claims that it was able to correct."
- **Cost**: one project took ~30 min with Fable 5.1 and no skills, ~1 hour with pstack. n=1, self-reported, no token figures. **Low confidence** — do not use this ratio to justify anything.
- **`arena`/`swarm` "fearless parallelism"** — the presenter explicitly disclaims it: "It is a big claim. I haven't used it enough to say that that is actually the case." **Low confidence.**

### Ecosystem Context

**F1 — SKILL.md is now the cross-agent lingua franca. (High confidence.)** pstack ships as an official Cursor marketplace plugin, and two independent community ports already run it on Claude Code and Codex: [michael-denyer/pstack-claude](https://github.com/michael-denyer/pstack-claude) and [ericlitman/open-pstack](https://github.com/ericlitman/open-pstack). Nobody rewrote the skills — the same `SKILL.md` files load in both ecosystems. This directly answers strategic question 1 in `research-context.md`: the format is durable enough to build on, and it already is what this repo builds on.

**F2 — Principles as individually-loadable leaf skills, with a citation rule. (High confidence.)** pstack's 21 principles are separate directories, each with its own `SKILL.md`, routed by `poteto-mode`, which states: *"name each principle that shaped a decision and the specific choice it changed. Cite only principles whose leaf SKILL.md you read this session."* `principle-build-the-lever` goes further: *"If you cited it and there is no codemod, script, generator, or delegate skill in the diff, you didn't apply it."* That is a falsifiable claim about principle application, not a vibe.

**F3 — `blast-radius` ships a 5-rung proof ladder. (High confidence.)** From "1. You said so. Worthless on its own." through "4. You ran it." to "5. You reproduced it in the running app," with the instruction to say which rung each safety fact stopped at.

**F4 — `why` reconstructs rationale from systems of record, not from agent memory. (High confidence.)** It fans out across git blame, `gh pr view` bodies, issue trackers, chat, and error tracking in parallel, then returns a cited read with an explicit epistemics reference.

### Project Comparison

#### F5 — Our verification *contract* is better than pstack's. Our verification *lever* does not exist.

[`plugins/harness/references/verification.md`](plugins/harness/references/verification.md) is genuinely stronger than `principle-prove-it-works`: it types `evidence.fixed_target`, defines three evidence levels, invalidates prior proof when either the target *or the oracle* changes, and gates `accepted` on both the delivered outcome and `evidence.outcome: proven`. pstack has no equivalent typed gate.

But pstack has `create-verification-skill` and `maintain-verification-skill`, which **generate and then keep updating a project-local skill that drives the real app** — interviewing the repo for surface, run command, drive mechanism, observable evidence, and isolation. Our closest thing is [`harness:computer-use`](plugins/harness/skills/computer-use/SKILL.md), which *performs* one bounded check and returns evidence. It leaves no reusable artifact behind. Next session re-derives the whole approach.

We specify proof precisely and produce nothing a reviewer can re-run. That is the single biggest gap, and by our own house rules it is a `build the lever` failure.

#### F6 — We do not apply our verification discipline to our own executable plugins. Measured:

| Plugin | Executables | bats files |
|---|---|---|
| harness | 22 | 29 |
| pm | 7 | 9 |
| product-pulse | 1 | 3 |
| **transcribe** | **7** | **0** |
| **generate** | **2** | **0** |
| site-capture | 0 | 0 |

The pattern inverts: the three plugins that are mostly *prose contracts* carry 41 bats files; the plugins that actually **execute shell against the outside world** carry zero. And there is **no `.github` directory at all** — no CI. Those 41 tests only run when someone remembers to run `run-tests.sh` locally.

#### F7 — That gap produced a live failure in this very session. Two provable bugs in `transcribe`.

Getting this report's transcript required working around both by hand.

**Bug 1 — tier 0 aborts instead of falling through.** [`plugins/transcribe/bin/transcribe:136`](plugins/transcribe/bin/transcribe:136) passes `--sub-lang "en.*,en-orig"`. The pattern `en.*` matches the machine-translated `en` track. yt-dlp attempts `en` first, gets `HTTP Error 429: Too Many Requests`, and **aborts the whole subtitle download** — it never reaches `en-orig`. Reproduced verbatim:

```
[info] lUhXa8GiXns: Downloading subtitles: en, en-orig
[info] Writing video subtitles to: t0/caps.en.vtt
ERROR: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests
```

Zero files written. Requesting `--sub-lang en-orig` **alone** succeeded on the first try (220 KB, 2,287 words). Compounding it: yt-dlp exits 0 on that error, so the `|| return 1` on line 138 does not fire — only the later `ls` guard saves it.

**Bug 2 — the dependency check guards the wrong artifact.** Tier 2 died with `ERR_MODULE_NOT_FOUND: Cannot find package 'playwright'`. Root cause chain, all confirmed:

1. `install.sh` writes a PATH shim at `~/.local/bin/transcribe` that hard-codes **one** runtime's cache: `exec /Users/timmoser/.codex/plugins/cache/studio-moser/transcribe/0.2.1/bin/transcribe`.
2. That Codex copy has **no `node_modules`**. The Claude Code copy at `~/.claude/plugins/cache/.../0.2.1/node_modules` **does** (playwright, playwright-core, fsevents). `npm install` ran for one runtime; the shim points at the other.
3. [`plugins/transcribe/scripts/verify-deps.sh:25`](plugins/transcribe/scripts/verify-deps.sh:25) checks `test -d "$HOME/Library/Caches/ms-playwright"` — the **browser binary cache**, which exists. It never checks for the `playwright` **npm package** under `PLUGIN_ROOT`. So the guard passes and the failure surfaces as a raw Node stack trace at import time.

This is the exact class `plugins/harness/scripts/portability-lint.sh` was written for — its own header says machine-specific absolute paths were "Found in the wild." That lint covers tracked file contents and symlink targets. It cannot see a shim `install.sh` writes at runtime into `~/.local/bin`.

#### F8 — Where we are ahead of pstack. Do not trade these away.

- **Change class.** Polish / Small / Feature with named escalators ([`house-rules.md`](plugins/harness/references/house-rules.md)) is a real answer to the "agent overkill" the video's own title concedes. pstack's `poteto-mode` reminder is binary — "Casual turn or user opts out -> don't." We size ceremony; they toggle it.
- **Typed `HarnessResult`.** `status` / `blockers` / `evidence` with an acceptance gate beats prose triggers.
- **Worktree discipline.** Our house rules mandate `git worktree add` for parallel work and document the real incident that motivated it — a PR that carried another session's unmerged refactor. That is the concrete mechanism behind pstack's `principle-separate-before-serializing-shared-state`, and we have the incident evidence they don't publish.
- **Approval boundaries.** pstack's `principle-never-block-on-the-human` ("Proceed, present the result, let the human course-correct") **conflicts** with our approval gates for outward-facing and irreversible actions. Do not adopt it.

#### F9 — Two pstack skills have no counterpart here, and both fill a real hole.

- **`blast-radius`.** Our `verification.md` has three coarse levels. pstack's five-rung ladder is actionable at the moment of a risky diff and forces you to name where each fact stopped. Our levels don't distinguish "I pointed at the line" from "I ran it."
- **`why`.** Our [Shelby integration](plugins/harness/references/shelby-integration.md) recalls what agents wrote down. It cannot answer *why* for anything decided before Shelby existed or outside an agent session. `why` reconstructs from git blame, PR bodies, and trackers — sources that predate any memory layer. [`plugins/pm/references/reconcile-context-and-adr.md`](plugins/pm/references/reconcile-context-and-adr.md) covers part of this, but only inside the reconcile workflow.

#### F10 — `unslop` vs our House Style.

Our House Style output style already does what `unslop` does, and arguably better. The delta is *where* it applies: an output style governs responses; pstack runs `deslop` as a **pre-commit** step, so the discipline reaches committed prose. Our house rules' pre-commit check covers secrets and input validation, not prose. Minor, but real for a repo whose product is mostly prose.

### Risks & Gaps

- **R1 — Product Pulse's video pipeline is silently degraded.** `deep-dive` Phase 2 mandates stopping if transcription fails. Both fallback tiers are broken on this machine right now. Every future video deep-dive fails until F7 is fixed. This one only survived because I bypassed the tool.
- **R2 — 41 bats files are decorative without CI.** No `.github/workflows`. A regression in `harness` lands unnoticed unless a human runs `run-tests.sh`.
- **R3 — The two runtime caches drift independently.** Codex and Claude Code each get their own plugin cache copy; `install.sh` privileges whichever ran last. Any plugin with runtime dependencies inherits this bug, not just `transcribe`.
- **R4 — Token cost.** `arena` and `interrogate` fan out 3-4 models on one problem. The video offers no token figures. Adopting them without a cost gate contradicts our own change-class discipline.
- **R5 — Adopting pstack wholesale would import `never-block-on-the-human`,** which is incompatible with our approval boundaries. Cherry-pick.

### Prior Research

- **`evidence-gated-agent-completion.md`** concluded that a worker's completion claim stays unverified until the parent reproduces named proof. pstack **confirms and extends** this: `principle-prove-it-works` says "trust artifacts, not self-reports," and `show-me-your-work` caught three of the agent's own false claims in the video's demo. The extension is that pstack ships a *generator* for the proof artifact; we stopped at the contract.
- **`agent-native-harness-and-pm.md`** ("Automate the Waiting, Preserve the Decisions") — pstack's `principle-never-block-on-the-human` pushes the same axis harder than we should follow. Our approval gates are a deliberate decision-preservation boundary, not waiting.
- **`model-harness-unbundling.md`** — pstack's cross-agent ports are strong new evidence for that report's thesis. The skills are the portable asset; the harness is swappable. Nothing contradicts prior conclusions.

### Sources

- [cursor/plugins — pstack](https://github.com/cursor/plugins/tree/main/pstack) — official source, 46 skills
- [pstack on the Cursor Marketplace](https://cursor.com/marketplace/cursor/pstack)
- [michael-denyer/pstack-claude](https://github.com/michael-denyer/pstack-claude) — Claude Code / Codex / OpenCode / Gemini port
- [ericlitman/open-pstack](https://github.com/ericlitman/open-pstack) — tracks Cursor upstream
- [Flavio Copes — A deep dive into pstack](https://flaviocopes.com/pstack/)
- [Leslie Li — Go Deep First: Notes on Lauren Tan's pstack](https://leslieli.dev/notes/go-deep-first-pstack/)
- [Cursor Docs — Plugins](https://cursor.com/docs/plugins)
- [Video: Pstack Is Agent Overkill. Use It Anyway!](https://www.youtube.com/watch?v=lUhXa8GiXns)

### Action Items

| # | Action | Why | Effort | Confidence |
|---|--------|-----|--------|------------|
| A1 | Fix `bin/transcribe:136` — request `en-orig` and `en` as **separate** yt-dlp invocations, taking the first that writes a file | A 429 on one language currently kills the whole tier; `en-orig` alone works. Blocks every video deep-dive today | Quick win | High |
| A2 | Fix `verify-deps.sh` to test for the `playwright` package under `PLUGIN_ROOT`, not just the browser cache; make the `~/.local/bin` shim runtime-agnostic or run `npm install` per cache copy | The guard passes while the import fails; the shim hard-codes one runtime's cache path | Quick win | High |
| A3 | Add a bats suite for `transcribe` and `generate` covering tier selection, dep-check failure, and caption parsing | 9 executables with zero tests; both live bugs would have been caught by a dep-check test | Moderate | High |
| A4 | Add `.github/workflows/tests.yml` running every plugin's `run-tests.sh` | 41 existing bats files never run automatically. Cheapest possible upgrade to actual coverage | Moderate | High |
| A5 | Build `harness:create-verification-skill` — a generator that emits a re-runnable project-local verification lever, plus a maintain counterpart | Our biggest gap. We define proof precisely and leave no artifact a reviewer can re-run. `computer-use` verifies once and forgets | Significant | High |
| A6 | Add the 5-rung proof ladder from `blast-radius` to `harness/references/verification.md`, and require naming the rung each safety fact reached | Our three levels can't distinguish "pointed at the line" from "ran it." The ladder is a drop-in refinement of an existing file | Quick win | Medium-High |
| A7 | Add a citation rule to house rules: name each principle that changed a decision, and for `build the lever`, require the artifact to be in the diff | Makes principle application falsifiable instead of claimable. pstack's exact wording is worth borrowing | Quick win | Medium |
| A8 | Extend `portability-lint.sh` (or add a companion) to check runtime-installed shims and per-cache dependency parity | F7 is a whole bug class, not one bug. Any plugin with runtime deps inherits it | Moderate | Medium |
| A9 | Consider a `why` skill that reconstructs rationale from git blame, PR bodies, and trackers | Shelby can't answer "why" for decisions predating it or made outside agent sessions | Moderate | Medium |
| A10 | Do **not** adopt `arena`, `swarm`, or `never-block-on-the-human` | The parallelism claim is explicitly unverified by its own presenter; the autonomy principle conflicts with our approval boundaries | — | High |
