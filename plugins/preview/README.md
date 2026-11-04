# Preview

Temporary private previews of local websites for AI-assisted development. A preview
outlives the agent session, opens as a real page in any browser on your tailnet devices,
and stops when you run `down` or `prune`, log out, or reboot.

## Skill

- `/preview:serve-preview` — start, list, verify, stop, or prune static and application
  previews.

## How it works

Each preview is a launchd job on `127.0.0.1`, published with the host's own
`tailscale serve --bg --https=<port>`. The job file lives in
`~/.config/agent-previews/previews/`, outside `~/Library/LaunchAgents`, so it does not
come back after a reboot. `prune` clears what a reboot leaves behind.

The workflow requires macOS, the Tailscale CLI, `jq`, and `python3`. It is private to
your tailnet and never enables Tailscale Funnel.

## Verification

```bash
./tests/run-tests.sh
```
