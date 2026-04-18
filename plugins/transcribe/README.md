# transcribe

Video transcription for Claude Code. Captions-first for YouTube; local mlx-whisper on Apple Silicon as the fallback.

Handles YouTube, YouTube Shorts, Instagram posts/Reels, TikTok, and Threads. YouTube URLs hit a captions tier first (seconds, no model download). Non-YouTube platforms and YouTube videos without captions fall through to yt-dlp + mlx-whisper, with a headless-Playwright + Chromium pipeline for Threads.

## Install

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh
```

Installs: yt-dlp, ffmpeg, Node.js, Playwright Chromium, mlx-whisper. Apple Silicon only.

## Usage

### As a slash command

```
/transcribe:transcribe <url>
```

### From the Bash tool (or terminal, after install)

```
transcribe <url>                  # captions-first for YouTube, whisper otherwise
transcribe <url> --json
transcribe <url> --force-whisper  # skip captions, always run whisper
```

### From another skill

```
Skill({ skill: "transcribe:transcribe", args: "<url>" })
```

## Configuration

| Env var          | Default                               | Purpose                                        |
|------------------|---------------------------------------|------------------------------------------------|
| `WHISPER_MODEL`  | `mlx-community/whisper-large-v3-mlx`  | mlx-whisper model HF repo                      |
| `HF_TOKEN`       | —                                     | HuggingFace token (higher rate limits)         |
| `FORCE_WHISPER`  | `0`                                   | When `1`, skip YouTube-caption tier (same as `--force-whisper`) |

## Output

**Markdown (default):**

```
# {title}

**Source:** {url}
**Platform:** YouTube
**Duration:** 0:19
**Model:** mlx-community/whisper-large-v3-mlx

{transcript}
```

**JSON (with `--json`):** includes timestamped segments.

## Scope and limitations

See the [design spec](../../docs/superpowers/specs/2026-04-14-transcribe-plugin-design.md) for what's in scope for v0.1.

## License

MIT
