# Research Scout

Deep-dive research and analysis of external reference materials against your current project. Analyzes YouTube videos, articles, GitHub repos, documentation, and code sources — then compares findings to your codebase with specific, actionable recommendations.

## Why

When you find a useful resource — a video, article, or repo — you want to know what it means for *your* project specifically. Not a generic summary, but a thorough cross-reference: what applies, what doesn't, what you're missing, and what you're already doing better.

Research Scout goes deep:
- **Full content extraction** — transcripts from videos, full text from articles, structure and source from repos
- **Ecosystem research** — investigates every tool, library, and pattern mentioned, including alternatives and recent developments
- **Project audit** — reads your codebase to understand your stack, architecture, and current approach
- **Cross-reference analysis** — compares findings against your project with specific file references and concrete suggestions

## Installation

```bash
/plugin install research-scout@studio-moser
```

## Usage

### `/research-scout:research-scout`

Share one or more links and ask to research them against your project.

```
# Analyze a video against your project
/research-scout:research-scout https://youtube.com/watch?v=... research this against the project

# Compare an article's recommendations
/research-scout:research-scout https://blog.example.com/microservices-patterns analyze this reference

# Deep-dive a repo
/research-scout:research-scout https://github.com/example/cool-lib compare to this project
```

The skill triggers on phrases like:
- "research this against the project"
- "analyze this reference"
- "compare to this project"

It does **not** trigger just because you share a link — the explicit research request is the signal.

## Output

The report includes:

- **Resource Summary** — Key takeaways with freshness/credibility assessment
- **Ecosystem Context** — Broader landscape beyond what the resource covers
- **Project Comparison** — Specific differences between recommendations and your codebase
- **Risks and Gaps** — Vulnerabilities or missing capabilities surfaced by the research
- **Sources** — Curated links for further reading
- **Action Items** — Prioritized suggestions with effort estimates

## License

MIT
