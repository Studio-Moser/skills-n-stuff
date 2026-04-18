---
name: transcribe
description: >-
  Fetch a spoken-word transcript from a video URL. Supports YouTube, YouTube
  Shorts, Instagram posts/Reels, TikTok, and Threads. Use whenever you need
  the words said in a video — for research, summarization, or analysis.
  Invoke with /transcribe:transcribe <url> or from Bash as `transcribe <url>`.
argument-hint: <video-url> [--json]
allowed-tools: Bash
---

# transcribe

Fetch a spoken-word transcript from a video URL. YouTube URLs try the uploader's captions first (seconds, no model download). Everything else — and YouTube videos without captions — falls through to audio extraction + mlx-whisper on Apple Silicon, with a headless-Playwright fallback for Threads and other yt-dlp-unsupported platforms.

## When to invoke

- The user gives you a YouTube, Shorts, Instagram, TikTok, or Threads URL and asks for a transcript, summary, analysis, or quote
- Another skill needs the spoken content of a video to do its job (e.g. research-scout analyzing a reference video)

## How to invoke

From the Bash tool:

```
transcribe <url>                  # default: captions-first for YouTube, whisper otherwise
transcribe <url> --json
transcribe <url> --force-whisper  # skip YouTube captions, always run whisper
```

The `transcribe` executable is on PATH once the plugin is installed.

From another skill, use the Skill tool:

```
Skill({ skill: "transcribe:transcribe", args: "<url>" })
```

## Output

**Default (markdown):**

```
# {title}

**Source:** {url}
**Platform:** {YouTube|Instagram|TikTok|Threads}
**Duration:** {mm:ss or "unknown"}
**Model:** mlx-community/whisper-large-v3-mlx

{transcript}
```

**With `--json`:** structured object with `title`, `url`, `platform`, `duration_seconds`, `model`, `tier` (`youtube-captions-manual`, `youtube-captions-auto`, `ytdlp`, or `playwright`), `text`, and `segments[]` with timestamps. The captions tiers return an empty `segments[]` — segment timing is only available when whisper runs.

## Dependencies

Install with:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh
```

Apple Silicon only in v0.1. Install deps: yt-dlp, ffmpeg, Node.js ≥ 20, Playwright Chromium, mlx-whisper.

## Model

Default model: `mlx-community/whisper-large-v3-mlx` (~3GB, downloaded on first use). Override per-call with the `WHISPER_MODEL` environment variable, for example:

```
WHISPER_MODEL=mlx-community/whisper-base-mlx transcribe <url>
```

Smaller models trade accuracy for speed. Use `whisper-base-mlx` (~140MB) for quick checks.

## Tiers

1. **YouTube captions (tier 0)** — `yt-dlp --write-sub --write-auto-sub` fetches the uploader's captions directly, no audio download, no whisper. Manual captions preferred; auto-generated is the fallback within this tier. YouTube URLs only. Seconds per video.
2. **yt-dlp + mlx-whisper (tier 1)** — downloads audio, converts to 16kHz WAV, transcribes locally. Used for non-YouTube platforms, YouTube videos without any captions, or when `--force-whisper` is set. Minutes per video.
3. **Playwright + mlx-whisper (tier 2)** — headless-browser extraction for Threads and other platforms yt-dlp can't reach.

The `Model:` line in the output reports which tier ran: `youtube-manual-captions`, `youtube-auto-captions`, or the whisper model name.

## Known limitations

- **Apple Silicon only for tiers 1 and 2.** Tier 0 (YouTube captions) works anywhere with yt-dlp + python3. Tier 1/2 need mlx-whisper, which is Apple Silicon only.
- **YouTube auto-captions are noisy.** Auto-generated captions miss punctuation, mis-transcribe names, and don't attribute speakers. Use `--force-whisper` when accuracy matters more than speed.
- **Silent videos hallucinate (whisper tiers only).** Whisper will invent text on silent or music-only audio. The plugin returns the transcript regardless but adds a stderr warning when repeated segments are detected.
- **Login-gated posts.** Public content only unless the user has signed into the persistent Playwright profile at `~/.cache/transcribe-plugin/playwright-profile/`.
- **No batching.** One URL per call. Use a shell loop for multiple.
- **Threads is flaky.** Threads post pages also render a feed of suggested videos, and Playwright's network capture can land on a neighbor instead of the target post. The extractor anchors to the `<video>` element's `currentSrc` and filters to segments sharing its CDN asset id, but expect occasional failures or mismatches. Retry or fall back to manual download for critical Threads transcripts.

## See also

- `references/integration-guide.md` — how other skills should invoke transcribe
