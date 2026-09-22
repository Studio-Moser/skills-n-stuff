# Preview

Durable, private local website previews for AI-assisted development. Preview
services survive an agent session, receive stable Tailscale Service URLs, and
appear in a tailnet-wide Preview Hub grouped by machine and project.

## Skill

- `/preview:serve-preview` — create, inspect, verify, or remove static and
  application previews; administer the shared DockTail router and Preview Hub.

## Runtime boundary

Reusable controller code and templates ship with this plugin. At first use they
are copied into a versioned bundle under `~/.config/agent-previews/runtime/` so
running containers never depend on an evictable plugin-cache path.

OAuth credentials, Tailscale state, Docker socket acceptance, and machine identity
remain under `~/.config/agent-previews/` and are never stored in this repository.

The workflow requires Docker, Tailscale, `curl`, and `jq`. It is private by
default and never enables Tailscale Funnel.

## Verification

```bash
./tests/run-tests.sh
```
