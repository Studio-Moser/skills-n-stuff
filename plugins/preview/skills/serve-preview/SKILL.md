---
name: serve-preview
description: >-
  Create, expose, inspect, or stop durable local website previews that must survive
  an agent session and remain privately reachable over Tailscale. Use for local
  preview sites, static reference sites, dev-server sharing, and requests to open
  a localhost site remotely. Do not use for public deployment.
---

# Serve Preview

Use the shared Docker and DockTail preview plane. A preview belongs to the machine,
not to the agent process that created it.

Resolve the controller from this skill's installed location before running a command.
Claude plugins expose it at
`$CLAUDE_PLUGIN_ROOT/skills/serve-preview/scripts/Preview.sh`; a Harness-managed
skills install normally exposes it at
`${AGENTS_REPO:-$HOME/.agents}/skills/serve-preview/scripts/Preview.sh`. If neither
applies, use the `scripts/Preview.sh` next to this `SKILL.md`. Set that absolute path
as `preview` in the examples below.

## Invariants

- Keep previews private to the tailnet. Never enable Funnel.
- Accept a lowercase DNS-safe short name and advertise it only inside the reserved
  `preview-*` Service namespace. A short name matches `^[a-z][a-z0-9-]{0,54}$`.
- Treat Service names as tailnet-wide. Refuse an existing name associated with a
  different preview router instead of silently creating a load-balanced Service.
- Give every preview `restart: unless-stopped` behavior.
- Put the application process itself in the managed container. A host process behind
  a proxy container or LaunchAgent is a migration bridge, not a finished preview.
- Give every preview its own managed Docker network. Connect only the DockTail
  Tailscale sidecar to that network; do not put unrelated previews together.
- Do not publish host ports unless the user specifically needs a localhost URL.
- Never place Tailscale secrets in a repository, command argument, or container
  environment. The router reads the secret from
  `~/.config/agent-previews/secrets/`; the non-secret OAuth client ID may appear in
  container metadata.
- Do not enable DockTail's `DELETE_UNUSED_SERVICES` or
  `SKIP_SHUTDOWN_CLEANUP` settings.
- Report the stable URL: `https://preview-<name>.<tailnet>.ts.net`.

## Static previews

Use the bundled controller instead of starting a foreground HTTP server:

```bash
"$preview" up-static <name> <directory> [project]
"$preview" verify <name>
```

The command serves the directory read-only from a pinned nginx image. Re-running it
reconciles only containers and networks created by this skill. It refuses to create
a preview unless the router is healthy.

Useful lifecycle commands:

```bash
"$preview" list
"$preview" url <name>
"$preview" logs
"$preview" down <name>
"$preview" doctor
```

`down` removes the preview container but leaves its Tailscale Service definition so
the same stable name can be reused later.

## Existing application containers

Prefer the project's existing Dockerfile or Compose service. Add only the routing
contract below, adapting port `3000` to the container's actual listening port:

```yaml
services:
  app:
    container_name: agent-preview-project-name
    restart: unless-stopped
    networks:
      - default
      - agent-preview-project-name
    labels:
      dev.studiomoser.agent-preview: "true"
      dev.studiomoser.agent-preview.kind: "app"
      dev.studiomoser.agent-preview.project: "Project Name"
      docktail.service.enable: "true"
      docktail.service.name: "preview-project-name"
      docktail.service.description: "Managed by Studio Moser agent preview workflow; project=Project%20Name; kind=app"
      docktail.service.port: "3000"
      docktail.service.service-port: "443"
      docktail.service.network: "agent-preview-project-name"
      docktail.tags: "tag:agent-preview"

networks:
  agent-preview-project-name:
    external: true
    name: agent-preview-project-name
```

Make sure the application listens on `0.0.0.0` inside its container. Keep source
mounts and framework-specific commands in the project's Compose configuration; do
not duplicate package installation or build logic in this skill. Development
containers may bind-mount source, but keep container-native dependencies and build
output in Docker volumes so Linux artifacts never overwrite host dependencies. Do not
publish a host port just to bridge an existing dev server. Before starting the project,
run `"$preview" prepare project-name`; this creates its isolated network and connects
the Tailscale sidecar.

After `docker compose up -d`, run `"$preview" verify project-name`. For custom
applications this proves the ownership marker, isolated network, labels, lack of
published ports, restart policy, and a direct 2xx response after restart. Also check
the project's expected page or health endpoint when a generic 2xx is insufficient.

## Preview Hub

Use the private Preview Hub to inspect workflow-owned Services across the tailnet,
grouped by their advertising router:

```bash
"$preview" hub-up
"$preview" hub-verify
"$preview" hub-url
```

The hub lists only `preview-*` Services tagged `tag:agent-preview` with this
workflow's ownership marker. It reads the Tailscale inventory using separate,
read-only OAuth credentials and probes preview URLs through the router's private
HTTP proxy. The proxy listens only on the control-network address, not on any
preview network. The hub never receives the Docker socket or the router's write
credential.

Read [DockTail Setup](references/DockTail_Setup.md) before configuring the hub's
OAuth credentials. Run one hub for the tailnet; additional preview routers appear
automatically when they use this workflow's machine-specific router identity.

## Router administration

Router setup changes Tailscale identity and authorization. Read
[DockTail Setup](references/DockTail_Setup.md) before running `router-up` or changing
credentials, tags, ACLs, images, or the shared Docker network.
