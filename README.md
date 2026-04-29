# Studio Moser — Claude Code Marketplace

A plugin marketplace for [Claude Code](https://code.claude.com) by Studio Moser.

## Installation

Add the marketplace:

```bash
# From GitHub
/plugin marketplace add Studio-Moser/skills-n-stuff

# Or from a local clone
/plugin marketplace add ./skills-n-stuff
```

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

### Product Pulse

Strategic intelligence system for product teams. Weekly strategy briefs, daily market research, and interactive sprint development.

**Skills:**
- `/product-pulse:setup` — Onboard a new project (run once)
- `/product-pulse:weekly-strategist` — Monday morning strategic analysis with 5 analyst agents
- `/product-pulse:daily-research` — Daily domain-specific research filtered through weekly strategy
- `/product-pulse:sprint-dev` — Interactive implementation with code review and testing

[Full documentation](plugins/product-pulse/README.md)

### Site Capture

Capture full-page screenshots of websites with scroll-triggered animation support. Handles bot-protected sites, cookie banners, and lazy-loaded content.

**Skills:**
- `/site-capture:capture` — Capture screenshots of one or more websites (Microlink API + Chrome fallback)
- `/site-capture:audit` — Audit existing screenshots for quality issues (wrong content, blank sections, errors)

[Full documentation](plugins/site-capture/README.md)

## License

MIT
