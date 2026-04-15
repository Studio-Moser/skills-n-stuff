# Integration Guide

For skill authors who want to use the `transcribe` skill to fetch video transcripts.

## Two ways to invoke

### 1. From Bash (recommended for simple pipelines)

```
transcribe <url>
transcribe <url> --json
```

The `transcribe` binary is on PATH once the plugin is installed. Output goes to stdout; logs go to stderr.

### 2. Via the Skill tool (recommended when LLM reasoning over the transcript is needed)

```
Skill({ skill: "transcribe:transcribe", args: "<url>" })
```

The skill loads with full context, runs the bash pipeline, and returns the markdown-formatted transcript to your conversation.

## Pattern for research skills

```markdown
When a user provides a video URL (YouTube, Shorts, Instagram, TikTok, Threads):

1. Call `transcribe <url>` from Bash to get the full transcript as markdown.
2. Treat the transcript as the primary source material for your analysis.
3. Preserve the source link in your output so the user can reference the original.

If `transcribe` exits non-zero, report the stderr output to the user and stop — do not try to analyze the video without its transcript.
```

## Gotchas

- **First call is slow.** The default whisper-large-v3 model downloads ~3GB on first use. Subsequent calls are fast.
- **Silent videos hallucinate.** Always check the transcript for obvious repetition (e.g. a sentence repeated 50 times) before treating it as ground truth.
- **Threads is slower** — it goes through Playwright. Budget 30-60 seconds for a short clip.
- **Don't cache transcripts silently.** If you're running inside a research pipeline, save the transcript alongside the report so the user can audit what the model actually saw.

## Example skill snippet

```markdown
## Fetching video transcripts

For any video URL (YouTube, Shorts, Instagram, TikTok, Threads), fetch the full transcript with the transcribe skill before analysis:

Bash: `transcribe <url>`

This returns a markdown document with title, source, platform, duration, and the full spoken text. Use the transcript as your primary source.
```

Copy-paste this section into any skill that analyzes video content.
