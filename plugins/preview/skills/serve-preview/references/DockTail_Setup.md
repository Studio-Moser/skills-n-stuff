# DockTail Setup

The router is one persistent tagged Tailscale sidecar plus DockTail. Each preview is
a native Tailscale Service tagged `tag:agent-preview`, not a separate tailnet device.

## One-time Tailscale configuration

In the Tailscale admin console:

1. Define `tag:server` and `tag:agent-preview`, then allow `tag:server` to advertise
   services carrying `tag:agent-preview`:

   ```json
   {
     "tagOwners": {
       "tag:server": ["autogroup:admin"],
          "tag:agent-preview": ["tag:server"]
     },
     "autoApprovers": {
       "services": {
       "tag:agent-preview": ["tag:server"]
       }
     }
   }
   ```

   Merge these keys into the existing policy. Do not replace unrelated grants,
   groups, tags, tests, or node attributes.

2. Create an OAuth client with exactly these grants:

   - Services: Write
   - Devices Core: Write
   - Auth Keys: Write

   When the credential form requests tags for Devices Core or Auth Keys, select only
   `tag:server`. DockTail applies `tag:agent-preview` to the Service definitions; it
   is not the sidecar device identity.

3. Save the client ID and secret locally. Do not paste either into chat or commit
   them:

   ```bash
   mkdir -p ~/.config/agent-previews/secrets
   chmod 700 ~/.config/agent-previews ~/.config/agent-previews/secrets
   install -m 600 /dev/null ~/.config/agent-previews/secrets/tailscale_oauth_client_id
   pbpaste > ~/.config/agent-previews/secrets/tailscale_oauth_client_id
   # Copy the secret, then run the equivalent pbpaste command for:
   # ~/.config/agent-previews/secrets/tailscale_oauth_client_secret
   ```

The controller refuses to start the router if either credential file is absent,
empty, symlinked, owned by another account, or group/world-readable.

## Preview Hub credential

The Preview Hub uses a different OAuth client so a compromise of the web process
cannot modify devices or Service definitions. Create a second OAuth client with
only these operations:

- Services: Read
- Devices Core: Read

Save its values with mode `600` as:

```bash
~/.config/agent-previews/secrets/tailscale_hub_oauth_client_id
~/.config/agent-previews/secrets/tailscale_hub_oauth_client_secret
```

The hub receives only those two files. It does not receive the router's write
credential, Tailscale LocalAPI socket, or Docker socket.

## Docker socket acceptance

DockTail requires the Docker socket. Despite the read-only filesystem mount, Docker
API access is effectively control of the Docker daemon: a compromised DockTail image
could create privileged containers, read mounted project files and credentials, or
alter other containers. Digest pinning prevents image-tag drift but does not contain
a vulnerability in that image.

The person operating this machine must explicitly accept that boundary before first
startup. Agents must not create the acceptance file on the person's behalf:

```bash
install -m 600 /dev/null ~/.config/agent-previews/docker_socket_risk_accepted
printf '%s\n' 'I accept DockTail Docker daemon access' > \
  ~/.config/agent-previews/docker_socket_risk_accepted
```

## Start and verify

Set `preview` to the absolute controller path described in the parent `SKILL.md`,
then run:

```bash
"$preview" router-up
"$preview" doctor
"$preview" up-static pilot /path/to/static/site
"$preview" verify pilot
"$preview" hub-up
"$preview" hub-verify
```

The router uses a control network plus one network per preview, so unrelated preview
containers cannot communicate laterally. Docker Desktop host networking is not
required. `Preview.sh prepare <name>` creates and attaches a custom application's
network before its Compose project starts.

Each router derives a machine-specific Tailscale hostname such as
`preview-router-studio-moser`. Preview Service names remain tailnet-wide; the
controller refuses to reuse a name already associated with a different router.

## Recovery

Stop the router without deleting its persistent Tailscale state:

```bash
"$preview" router-down
```

Remove a preview with `"$preview" down <name>`. DockTail drains the advertisement on
graceful shutdown but intentionally retains the Service definition. Removing the
tagged `agent-preview-router` device, OAuth client, or Service definition is an
admin-console action and must target only those resources.

## Security boundaries

- DockTail has effective Docker daemon control. Startup requires the person's explicit
  acceptance file, and the image is pinned by digest to prevent tag drift.
- The OAuth secret is mounted from a mode-600 file and appears in container metadata
  only as a file path.
- The router never configures Tailscale Funnel.
- Automatic deletion of unused Service definitions remains disabled.
- Docker Desktop must be running for previews. Enable its login item separately if
  previews must return automatically after a Mac reboot.

Authoritative references:

- <https://docktail.org/docs/>
- <https://tailscale.com/docs/features/tailscale-services>
