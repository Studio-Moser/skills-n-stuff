# skills-n-stuff

[![skills.sh](https://skills.sh/b/Studio-Moser/skills-n-stuff)](https://skills.sh/Studio-Moser/skills-n-stuff)

Product research, market intelligence, and content tools for AI-native teams. A plugin collection for [Claude Code](https://code.claude.com) by [Studio Moser](https://studiomoser.design).

## Installation

Add the marketplace:

```bash
# From GitHub
/plugin marketplace add Studio-Moser/skills-n-stuff

# Or from a local clone
/plugin marketplace add ./skills-n-stuff
```

Then turn on auto-update — Claude Code leaves it **off** by default for third-party marketplaces, so without this you stay on whatever version you first installed: `/plugin` → **Marketplaces** → `studio-moser` → **Enable auto-update**. (Or refresh by hand any time: `/plugin marketplace update studio-moser` then `/plugin update <plugin>@studio-moser`.)

Then install plugins:

```bash
/plugin install product-pulse@studio-moser
```

### Other agents (skills only)

For non-Claude-Code agents (Cursor, Codex, Gemini CLI, OpenCode, etc.), the [`skills` CLI](https://github.com/vercel-labs/skills) can install just the `SKILL.md` prompts into your agent's skills directory:

```bash
npx skills add Studio-Moser/skills-n-stuff
```

Note: subagents, hooks, and bundled scripts (e.g., the `transcribe` CLI) are Claude-Code-only and aren't included by this path.

## Plugins

### Figma Design

Author high-quality designs directly into Figma via the Dev Mode MCP. Fuses Claude's `frontend-design` aesthetic engine with a `DESIGN.md` token contract and `figma-use` authoring discipline so code-to-design output matches the quality you get from Claude in HTML/CSS. Branches across existing Figma systems, code-only systems, and greenfield.

**Skills:**
- `/figma-design:designing-in-figma` — Build screens, UIs, mockups, and components into Figma (code-to-design) with the full aesthetic + token + auto-layout workflow

[Full documentation](plugins/figma-design/README.md)

### Product Pulse

Strategic intelligence system for product teams. Weekly strategy briefs, daily market research, and deep-dive analysis — a three-cadence intelligence system.

**Skills:**
- `/product-pulse:setup` — Onboard a new project (run once)
- `/product-pulse:weekly-strategist` — Monday morning strategic analysis with 5 analyst agents
- `/product-pulse:daily-research` — Daily domain-specific research filtered through weekly strategy
- `/product-pulse:deep-dive` — Deep-dive research on external resources (videos, articles, repos, docs)

[Full documentation](plugins/product-pulse/README.md)

### PM

Backend-agnostic project management for AI-native teams. Ingests research reports, triages and specs work items, manages sprint execution with sub-agents, syncs with GitHub Issues.

**Skills:**
- `/pm:setup` — Onboard a project (run once)
- `/pm:ingest` — Read research reports and create tracked issues
- `/pm:triage` — Spec, score, and promote items to ready-for-agent
- `/pm:reconcile` — Sync reality with the tracker (completion, stale, blockers)
- `/pm:sprint-dev` — Pick ready work and execute with sub-agents
- `/pm:dev-task` — Interactive, guided single-task dev workflow (plan → approve → build → review → verify → PR)

[Full documentation](plugins/pm/README.md)

### Harness

Owns universal agent rules, personal configuration across machines, semantic
routing, bounded execution, and evidence-bearing results.

**Skills:**
- `/harness:setup` — configure the personal agents repository, links, runtimes, and rubric
- `/harness:sync` — reconcile your personal agent repository with this machine
- `/harness:model-rubric` — create or refresh your user-global model-routing rubric

[Full documentation](plugins/harness/README.md)

### Site Capture

Capture full-page screenshots of websites with scroll-triggered animation support. Handles bot-protected sites, cookie banners, and lazy-loaded content.

**Skills:**
- `/site-capture:capture` — Capture screenshots of one or more websites (Microlink API + Chrome fallback)
- `/site-capture:audit` — Audit existing screenshots for quality issues (wrong content, blank sections, errors)

[Full documentation](plugins/site-capture/README.md)

### Generate

Governed image, video, and audio generation over the Kie.ai MCP. Prices a batch and stops for confirmation before spending, downloads every result locally before its URL expires, and logs the prompt that produced each file.

**Skills:**
- `/generate:generate` — Generate media with a budget guard, local archive, and prompt log

[Full documentation](plugins/generate/README.md)

### Research Scout (Deprecated)

> **Deprecated:** Use `/product-pulse:deep-dive` instead.

Deep-dive research and analysis. Now integrated into Product Pulse.

### Transcribe

Video transcription for Claude Code. Captions-first for YouTube; local mlx-whisper on Apple Silicon as the fallback. Handles YouTube, YouTube Shorts, Instagram posts/Reels, TikTok, and Threads.

**Skills:**
- `/transcribe:transcribe` — Fetch a spoken-word transcript from a video URL

[Full documentation](plugins/transcribe/README.md)

## License

MIT
