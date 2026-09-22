#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
SKILL_DIR="$(dirname -- "$SCRIPT_DIR")"
CONFIG_ROOT="${PREVIEW_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-previews}"
SECRETS_DIR="$CONFIG_ROOT/secrets"
RUNTIME_BUNDLE_VERSION="0.1.1"
RUNTIME_BUNDLE="$CONFIG_ROOT/runtime/$RUNTIME_BUNDLE_VERSION"
ROUTER_COMPOSE="$RUNTIME_BUNDLE/DockTail.compose.yaml"
STATIC_TEMPLATE="$RUNTIME_BUNDLE/Static_Preview.conf.template"
HUB_APP="$RUNTIME_BUNDLE/Preview_Hub"
CONTROL_NETWORK_NAME="agent-preview-control"
ROUTER_PROJECT="agent-preview-router"
CONTAINER_PREFIX="agent-preview-"
OWNERSHIP_LABEL="dev.studiomoser.agent-preview=true"
NGINX_IMAGE="nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de"
HUB_IMAGE="python:3.13-alpine@sha256:79e7a9b9ff1cbceff819f856fb374477792a5967759d94df266de7b7b4120e6f"
SERVICE_COMMENT_PREFIX="Managed by Studio Moser agent preview workflow"

usage() {
  cat <<'EOF'
Usage: Preview.sh <command> [arguments]

Commands:
  router-up                 Start the persistent Tailscale + DockTail router
  router-down               Stop the router and keep its persistent state
  router-status             Show router containers
  prepare <name>            Create/attach an isolated app-preview network
  up-static <name> <dir> [project]
                            Serve a directory as a durable private preview
  down <name>               Remove one managed preview container
  list                      List managed previews
  url <name>                Print a preview's stable Tailscale URL
  verify <name>             Require the preview URL to return HTTP success
  hub-up                    Start the tailnet-wide Preview Hub
  hub-down                  Stop the Preview Hub container
  hub-status                Show Preview Hub status
  hub-verify                Verify the Preview Hub API and restart behavior
  hub-url                   Print the Preview Hub URL
  logs                      Follow recent router logs
  doctor                    Check local prerequisites and router readiness
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

stage_runtime_bundle() {
  local runtime_root created=false
  runtime_root="$CONFIG_ROOT/runtime"
  mkdir -p "$runtime_root"
  chmod 700 "$CONFIG_ROOT" "$runtime_root"

  if mkdir "$RUNTIME_BUNDLE" 2>/dev/null; then
    created=true
    if ! cp "$SKILL_DIR/assets/DockTail.compose.yaml" "$ROUTER_COMPOSE" ||
       ! cp "$SKILL_DIR/assets/Static_Preview.conf.template" "$STATIC_TEMPLATE" ||
       ! cp -R "$SKILL_DIR/assets/Preview_Hub" "$HUB_APP" ||
       ! touch "$RUNTIME_BUNDLE/.complete"; then
      rm -rf "$RUNTIME_BUNDLE"
      fail "could not stage Preview runtime bundle $RUNTIME_BUNDLE_VERSION"
    fi
  fi

  [[ -f "$RUNTIME_BUNDLE/.complete" &&
     -f "$ROUTER_COMPOSE" &&
     -f "$STATIC_TEMPLATE" &&
     -f "$HUB_APP/Preview_Hub.py" ]] ||
    fail "Preview runtime bundle is incomplete: $RUNTIME_BUNDLE"
  [[ "$created" == false ]] || chmod -R u=rwX,go= "$RUNTIME_BUNDLE"
}

validate_name() {
  local name="${1:-}"
  [[ "$name" =~ ^[a-z][a-z0-9-]{0,54}$ ]] ||
    fail "preview name must match ^[a-z][a-z0-9-]{0,54}$"
}

validate_project() {
  local project="${1:-}"
  [[ -n "$project" && ${#project} -le 80 ]] ||
    fail "project name must contain 1 to 80 characters"
  [[ ! "$project" =~ [[:cntrl:]] ]] || fail "project name must not contain control characters"
}

service_comment() {
  local kind="$1"
  local project="$2"
  local encoded_project
  encoded_project="$(printf '%s' "$project" | jq -sRr @uri)"
  printf '%s; project=%s; kind=%s\n' "$SERVICE_COMMENT_PREFIX" "$encoded_project" "$kind"
}

service_name() {
  printf 'preview-%s\n' "$1"
}

container_name() {
  printf '%s%s\n' "$CONTAINER_PREFIX" "$1"
}

preview_network_name() {
  container_name "$1"
}

router_hostname() {
  local machine_name machine_slug
  machine_name="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
  machine_slug="$(printf '%s' "$machine_name" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' |
    cut -c1-40)"
  [[ -n "$machine_slug" ]] || fail "could not derive a preview router hostname"
  printf 'preview-router-%s\n' "$machine_slug"
}

ensure_control_network() {
  if docker network inspect "$CONTROL_NETWORK_NAME" >/dev/null 2>&1; then
    local owned
    owned="$(docker network inspect --format '{{ index .Labels "dev.studiomoser.agent-preview" }}' "$CONTROL_NETWORK_NAME")"
    [[ "$owned" == true ]] || fail "refusing to use an unmanaged network: $CONTROL_NETWORK_NAME"
  else
    docker network create \
      --label dev.studiomoser.agent-preview=true \
      "$CONTROL_NETWORK_NAME" >/dev/null
  fi
}

control_proxy_ip() {
  local existing gateway a b c d
  existing="$(docker inspect --format "{{with index .NetworkSettings.Networks \"$CONTROL_NETWORK_NAME\"}}{{.IPAddress}}{{end}}" agent-preview-tailscale 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    printf '%s\n' "$existing"
    return
  fi

  gateway="$(docker network inspect --format '{{(index .IPAM.Config 0).Gateway}}' "$CONTROL_NETWORK_NAME" 2>/dev/null || true)"
  IFS=. read -r a b c d <<<"$gateway"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ && "$d" =~ ^[0-9]+$ && "$d" -lt 254 ]] ||
    fail "could not derive a private control-network address from gateway: ${gateway:-missing}"
  printf '%s.%s.%s.%s\n' "$a" "$b" "$c" "$((d + 1))"
}

ensure_preview_network() {
  local name="$1"
  local network
  network="$(preview_network_name "$name")"
  if docker network inspect "$network" >/dev/null 2>&1; then
    local owned
    owned="$(docker network inspect --format '{{ index .Labels "dev.studiomoser.agent-preview" }}' "$network")"
    [[ "$owned" == "true" ]] || fail "refusing to use an unmanaged network: $network"
  else
    docker network create \
      --label dev.studiomoser.agent-preview=true \
      --label "dev.studiomoser.agent-preview.name=$name" \
      "$network" >/dev/null
  fi
}

connect_router_network() {
  local name="$1"
  local network
  network="$(preview_network_name "$name")"
  router_ready
  if ! docker inspect --format '{{json .NetworkSettings.Networks}}' agent-preview-tailscale |
      jq -e --arg network "$network" 'has($network)' >/dev/null; then
    docker network connect "$network" agent-preview-tailscale
  fi
}

router_ready() {
  local tailscale_health docktail_health expected_proxy
  tailscale_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' agent-preview-tailscale 2>/dev/null || true)"
  docktail_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' agent-preview-docktail 2>/dev/null || true)"
  [[ "$tailscale_health" == "healthy" && "$docktail_health" == "healthy" ]] ||
    fail "preview router is not healthy (tailscale=${tailscale_health:-missing}, docktail=${docktail_health:-missing})"
  expected_proxy="TS_OUTBOUND_HTTP_PROXY_LISTEN=$(control_proxy_ip):1055"
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' agent-preview-tailscale |
    grep -Fxq "$expected_proxy" || fail "preview router proxy is not bound only to the control network"
}

credential_path() {
  printf '%s/%s\n' "$SECRETS_DIR" "$1"
}

check_credential_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]] ||
    fail "credential must be a non-empty regular file, not a symlink: $path"
  local mode owner
  mode="$(stat -f '%Lp' "$path")"
  owner="$(stat -f '%u' "$path")"
  [[ "$owner" == "$(id -u)" ]] || fail "credential file has the wrong owner: $path"
  (( (8#$mode & 8#077) == 0 )) ||
    fail "credential file must not be group/world accessible: $path (mode $mode)"
}

oauth_client_id() {
  local path
  path="$(credential_path tailscale_oauth_client_id)"
  check_credential_file "$path"
  tr -d '\r\n' < "$path"
}

oauth_access_token() {
  local client_id_encoded client_secret_encoded response
  check_credential_file "$(credential_path tailscale_oauth_client_secret)"
  client_id_encoded="$(oauth_client_id | jq -sRr @uri)"
  client_secret_encoded="$(tr -d '\r\n' < "$(credential_path tailscale_oauth_client_secret)" | jq -sRr @uri)"
  response="$(
    printf 'grant_type=client_credentials&client_id=%s&client_secret=%s' "$client_id_encoded" "$client_secret_encoded" |
      curl --fail --silent --show-error --max-time 15 \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data-binary @- \
        https://api.tailscale.com/api/v2/oauth/token
  )"
  printf '%s' "$response" | jq -er '.access_token | select(length > 0)'
}

assert_service_owned_or_absent() {
  local name="$1"
  local service token response_file status
  service="svc:$(service_name "$name")"
  token="$(oauth_access_token)"
  response_file="$(mktemp)"
  status="$(
    printf 'header = "Authorization: Bearer %s"\n' "$token" |
      curl --config - --silent --show-error --max-time 15 \
        --output "$response_file" --write-out '%{http_code}' \
        "https://api.tailscale.com/api/v2/tailnet/-/services/$service"
  )"

  case "$status" in
    404)
      rm -f "$response_file"
      return 0
      ;;
    200)
      if jq -e --arg prefix "$SERVICE_COMMENT_PREFIX" \
          '(.comment == $prefix or (.comment | startswith($prefix + "; "))) and
           (.tags | index("tag:agent-preview") != null)' \
          "$response_file" >/dev/null; then
        rm -f "$response_file"
        assert_service_host_available "$service" "$token"
        return 0
      fi
      rm -f "$response_file"
      fail "Tailscale Service $service already exists without this workflow's ownership marker"
      ;;
    *)
      local api_message
      api_message="$(jq -r '.message // "unknown API error"' "$response_file" 2>/dev/null || true)"
      rm -f "$response_file"
      fail "could not verify ownership of $service (HTTP $status: $api_message)"
      ;;
  esac
}

assert_service_host_available() {
  local service="$1"
  local token="$2"
  local current_node response_file status foreign_hosts
  current_node="$(docker exec agent-preview-tailscale tailscale status --json |
    jq -er '.Self.ID | select(length > 0)')"
  response_file="$(mktemp)"
  status="$(
    printf 'header = "Authorization: Bearer %s"\n' "$token" |
      curl --config - --silent --show-error --max-time 15 \
        --output "$response_file" --write-out '%{http_code}' \
        "https://api.tailscale.com/api/v2/tailnet/-/services/$service/devices"
  )"
  [[ "$status" == 200 ]] || {
    rm -f "$response_file"
    fail "could not inspect hosts for existing Tailscale Service $service (HTTP $status)"
  }
  foreign_hosts="$(jq -r --arg node "$current_node" \
    '[.hosts[]? | select(.nodeId != $node)] | length' "$response_file")"
  rm -f "$response_file"
  [[ "$foreign_hosts" == 0 ]] ||
    fail "Tailscale Service $service is already associated with another preview router; choose a unique name"
}

tailnet_suffix() {
  tailscale status --json 2>/dev/null |
    jq -er '.MagicDNSSuffix // .CurrentTailnet.MagicDNSSuffix | select(length > 0)'
}

preview_url() {
  local name="$1"
  printf 'https://%s.%s\n' "$(service_name "$name")" "$(tailnet_suffix)"
}

router_compose() {
  stage_runtime_bundle
  PREVIEW_CONFIG_DIR="$CONFIG_ROOT" \
    PREVIEW_ROUTER_CONTROL_IP="$(control_proxy_ip)" \
    PREVIEW_ROUTER_HOSTNAME="$(router_hostname)" \
    TAILSCALE_OAUTH_CLIENT_ID="${TAILSCALE_OAUTH_CLIENT_ID:-}" \
    docker compose --project-name "$ROUTER_PROJECT" -f "$ROUTER_COMPOSE" "$@"
}

router_compose_authenticated() {
  local client_id
  stage_runtime_bundle
  client_id="$(oauth_client_id)"
  check_credential_file "$(credential_path tailscale_oauth_client_secret)"
  PREVIEW_CONFIG_DIR="$CONFIG_ROOT" \
    PREVIEW_ROUTER_CONTROL_IP="$(control_proxy_ip)" \
    PREVIEW_ROUTER_HOSTNAME="$(router_hostname)" \
    TAILSCALE_OAUTH_CLIENT_ID="$client_id" \
    docker compose --project-name "$ROUTER_PROJECT" -f "$ROUTER_COMPOSE" "$@"
}

router_up() {
  require_command docker
  mkdir -p "$SECRETS_DIR"
  chmod 700 "$CONFIG_ROOT" "$SECRETS_DIR"
  local acceptance="$CONFIG_ROOT/docker_socket_risk_accepted"
  [[ -f "$acceptance" && ! -L "$acceptance" ]] ||
    fail "Docker socket risk has not been accepted; read references/DockTail_Setup.md"
  grep -Fxq 'I accept DockTail Docker daemon access' "$acceptance" ||
    fail "Docker socket risk acceptance file has unexpected content"
  ensure_control_network
  router_compose_authenticated up -d
  while IFS= read -r network; do
    [[ -n "$network" ]] || continue
    if ! docker inspect --format '{{json .NetworkSettings.Networks}}' agent-preview-tailscale |
        jq -e --arg network "$network" 'has($network)' >/dev/null; then
      docker network connect "$network" agent-preview-tailscale
    fi
  done < <(docker network ls --filter label=dev.studiomoser.agent-preview=true --format '{{.Name}}' |
    grep '^agent-preview-' | grep -v '^agent-preview-control$' || true)
  local attempt
  for attempt in {1..30}; do
    local tailscale_health docktail_health
    tailscale_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' agent-preview-tailscale 2>/dev/null || true)"
    docktail_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' agent-preview-docktail 2>/dev/null || true)"
    if [[ "$tailscale_health" == "healthy" && "$docktail_health" == "healthy" ]]; then
      break
    fi
    sleep 2
  done
  router_ready
  docker exec agent-preview-tailscale tailscale set --hostname="$(router_hostname)"
  router_compose ps
}

router_down() {
  require_command docker
  router_compose down
}

router_status() {
  require_command docker
  router_compose ps
}

managed_container_id() {
  local name="$1"
  docker ps -aq --filter "name=^/$(container_name "$name")$" | head -n 1
}

prepare_preview() {
  local name="${1:-}"
  validate_name "$name"
  require_command docker
  stage_runtime_bundle
  router_ready
  assert_service_owned_or_absent "$name"
  ensure_preview_network "$name"
  connect_router_network "$name"
  printf '%s\n' "$(preview_network_name "$name")"
}

assert_managed() {
  local id="$1"
  local owned
  owned="$(docker inspect --format '{{ index .Config.Labels "dev.studiomoser.agent-preview" }}' "$id")"
  [[ "$owned" == "true" ]] || fail "refusing to modify an unmanaged container: $id"
}

container_id_by_name() {
  docker ps -aq --filter "name=^/$1$" | head -n 1
}

recover_container_replacement() {
  local canonical="$1"
  local next="${canonical}-next"
  local previous="${canonical}-previous"
  local canonical_id next_id previous_id
  canonical_id="$(container_id_by_name "$canonical")"
  next_id="$(container_id_by_name "$next")"
  previous_id="$(container_id_by_name "$previous")"

  [[ -z "$canonical_id" ]] || assert_managed "$canonical_id"
  [[ -z "$next_id" ]] || assert_managed "$next_id"
  [[ -z "$previous_id" ]] || assert_managed "$previous_id"

  if [[ -n "$canonical_id" ]]; then
    [[ -z "$next_id" ]] || docker rm -f "$next_id" >/dev/null
    [[ -z "$previous_id" ]] || docker rm -f "$previous_id" >/dev/null
  elif [[ -n "$previous_id" ]]; then
    docker rename "$previous" "$canonical"
    docker start "$canonical" >/dev/null
    [[ -z "$next_id" ]] || docker rm -f "$next_id" >/dev/null
  elif [[ -n "$next_id" ]]; then
    docker rm -f "$next_id" >/dev/null
  fi
}

rollback_container_replacement() {
  local canonical="$1"
  local previous="${canonical}-previous"
  docker rm -f "$canonical" >/dev/null 2>&1 || true
  if [[ -n "$(container_id_by_name "$previous")" ]]; then
    docker rename "$previous" "$canonical"
    docker start "$canonical" >/dev/null
  fi
}

CUTOVER_CANONICAL=""

recover_failed_cutover() {
  local status=$?
  trap - ERR INT TERM
  [[ -z "$CUTOVER_CANONICAL" ]] || recover_container_replacement "$CUTOVER_CANONICAL"
  CUTOVER_CANONICAL=""
  (( status != 0 )) || status=1
  exit "$status"
}

begin_container_cutover() {
  CUTOVER_CANONICAL="$1"
  trap recover_failed_cutover ERR INT TERM
}

end_container_cutover() {
  trap - ERR INT TERM
  CUTOVER_CANONICAL=""
}

wait_for_static_container() {
  local id="$1"
  local network="$2"
  local expected_service="$3"
  local attempt container_ip headers
  for attempt in {1..30}; do
    container_ip="$(docker inspect --format "{{with index .NetworkSettings.Networks \"$network\"}}{{.IPAddress}}{{end}}" "$id")"
    if [[ -n "$container_ip" ]] &&
       headers="$(docker exec agent-preview-tailscale sh -c \
         'wget -qSO- --timeout=5 "$1" >/dev/null' sh "http://$container_ip:80/" 2>&1)" &&
       grep -Eiq "^[[:space:]]*X-Agent-Preview-Name: ${expected_service}[[:space:]]*$" <<<"$headers"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_healthy_container() {
  local id="$1"
  local attempt state
  for attempt in {1..60}; do
    state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)"
    [[ "$state" == healthy ]] && return 0
    [[ "$state" == exited || "$state" == dead ]] && return 1
    sleep 1
  done
  return 1
}

up_static() {
  local name="${1:-}"
  local source_dir="${2:-}"
  local project="${3:-${1:-}}"
  validate_name "$name"
  validate_project "$project"
  [[ -n "$source_dir" ]] || fail "up-static requires a directory"
  [[ -d "$source_dir" ]] || fail "directory not found: $source_dir"
  source_dir="$(CDPATH= cd -- "$source_dir" && pwd -P)"

  require_command docker
  stage_runtime_bundle
  router_ready
  assert_service_owned_or_absent "$name"
  ensure_preview_network "$name"
  connect_router_network "$name"

  local network service description
  network="$(preview_network_name "$name")"
  service="$(service_name "$name")"
  description="$(service_comment static "$project")"

  local canonical next previous old_id id
  canonical="$(container_name "$name")"
  next="${canonical}-next"
  previous="${canonical}-previous"
  recover_container_replacement "$canonical"
  old_id="$(managed_container_id "$name")"
  [[ -z "$old_id" ]] || assert_managed "$old_id"

  if ! docker run -d \
    --name "$next" \
    --restart unless-stopped \
    --network "$network" \
    --env 'NGINX_ENVSUBST_FILTER=^PREVIEW_SERVICE_NAME$' \
    --env "PREVIEW_SERVICE_NAME=$service" \
    --label "$OWNERSHIP_LABEL" \
    --label dev.studiomoser.agent-preview.kind=static \
    --label "dev.studiomoser.agent-preview.project=$project" \
    --label "dev.studiomoser.agent-preview.source=$source_dir" \
    --label docktail.service.enable=true \
    --label "docktail.service.name=$service" \
    --label "docktail.service.description=$description" \
    --label docktail.service.port=80 \
    --label docktail.service.service-port=443 \
    --label "docktail.service.network=$network" \
    --label docktail.tags=tag:agent-preview \
    --mount "type=bind,source=$source_dir,target=/usr/share/nginx/html,readonly" \
    --mount "type=bind,source=$STATIC_TEMPLATE,target=/etc/nginx/templates/default.conf.template,readonly" \
    "$NGINX_IMAGE" >/dev/null; then
    fail "could not start replacement preview container; existing preview was preserved"
  fi

  id="$(container_id_by_name "$next")"
  if ! wait_for_static_container "$id" "$network" "$service"; then
    docker rm -f "$id" >/dev/null
    fail "replacement preview failed its direct health check; existing preview was preserved"
  fi

  begin_container_cutover "$canonical"
  if [[ -n "$old_id" ]]; then
    docker rename "$canonical" "$previous"
    docker stop "$previous" >/dev/null
  fi
  docker rename "$next" "$canonical"
  end_container_cutover

  if ! wait_for_preview "$name" "$id"; then
    rollback_container_replacement "$canonical"
    fail "replacement preview failed its tailnet check; previous preview was restored"
  fi
  [[ -z "$old_id" ]] || docker rm -f "$previous" >/dev/null
  printf '%s\n' "$(preview_url "$name")"
}

down_preview() {
  local name="${1:-}"
  validate_name "$name"
  require_command docker

  local id
  id="$(managed_container_id "$name")"
  [[ -n "$id" ]] || fail "managed preview not found: $name"
  assert_managed "$id"
  docker rm -f "$id" >/dev/null
  local network
  network="$(preview_network_name "$name")"
  if docker network inspect "$network" >/dev/null 2>&1; then
    local owned
    owned="$(docker network inspect --format '{{ index .Labels "dev.studiomoser.agent-preview" }}' "$network")"
    [[ "$owned" == "true" ]] || fail "refusing to remove an unmanaged network: $network"
    docker network disconnect "$network" agent-preview-tailscale >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null
  fi
  printf 'removed %s\n' "$(container_name "$name")"
}

list_previews() {
  require_command docker
  local suffix="unavailable"
  if command -v tailscale >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    suffix="$(tailnet_suffix 2>/dev/null || printf 'unavailable')"
  fi
  docker ps -a \
    --filter "label=$OWNERSHIP_LABEL" \
    --format '{{.Names}}\t{{.Status}}\t{{.Label "dev.studiomoser.agent-preview.kind"}}\t{{.Label "docktail.service.name"}}\t{{.Label "dev.studiomoser.agent-preview.project"}}\t{{.Label "dev.studiomoser.agent-preview.source"}}' |
    while IFS=$'\t' read -r container status kind service project source; do
      [[ -n "$container" ]] || continue
      [[ "$kind" == static || "$kind" == app ]] || continue
      printf '%s\t%s\thttps://%s.%s\t%s\t%s\n' "$container" "$status" "$service" "$suffix" "$project" "$source"
    done
}

verify_contract() {
  local name="$1"
  local id="$2"
  local expected_service restart network published kind
  [[ -n "$id" ]] || fail "managed preview not found: $name"
  assert_managed "$id"
  kind="$(docker inspect --format '{{ index .Config.Labels "dev.studiomoser.agent-preview.kind" }}' "$id")"
  [[ "$kind" == "static" || "$kind" == "app" ]] || fail "preview kind must be static or app"
  expected_service="$(service_name "$name")"
  restart="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$id")"
  [[ "$restart" == "unless-stopped" ]] || fail "preview restart policy is not unless-stopped"
  network="$(preview_network_name "$name")"
  docker inspect --format '{{json .NetworkSettings.Networks}}' "$id" |
    jq -e --arg network "$network" --arg control "$CONTROL_NETWORK_NAME" \
      'has($network) and (has($control) | not)' >/dev/null ||
    fail "preview is not isolated from the control network"
  published="$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$id")"
  [[ "$published" == "null" || "$published" == "{}" ]] || fail "preview unexpectedly publishes a host port"
  [[ "$(docker inspect --format '{{ index .Config.Labels "docktail.service.name" }}' "$id")" == "$expected_service" ]] ||
    fail "preview service label does not match the reserved namespace"
  [[ "$(docker inspect --format '{{ index .Config.Labels "docktail.service.description" }}' "$id")" == "$SERVICE_COMMENT_PREFIX"* ]] ||
    fail "preview is missing the Service ownership marker"
  [[ -n "$(docker inspect --format '{{ index .Config.Labels "dev.studiomoser.agent-preview.project" }}' "$id")" ]] ||
    fail "preview is missing project metadata"
  [[ "$(docker inspect --format '{{ index .Config.Labels "docktail.tags" }}' "$id")" == "tag:agent-preview" ]] ||
    fail "preview is missing the reserved Service tag"
}

wait_for_preview() {
  local name="$1"
  local id="$2"
  local url expected_service kind deadline headers code
  url="$(preview_url "$name")"
  expected_service="$(service_name "$name")"
  kind="$(docker inspect --format '{{ index .Config.Labels "dev.studiomoser.agent-preview.kind" }}' "$id")"
  deadline=$((SECONDS + 180))

  while (( SECONDS < deadline )); do
    headers="$(mktemp)"
    code="$(curl --silent --show-error --max-time 5 --max-redirs 0 \
      --dump-header "$headers" --output /dev/null --write-out '%{http_code}' "$url" || true)"
    if [[ "$code" =~ ^2[0-9][0-9]$ ]] &&
       { [[ "$kind" == "app" ]] || grep -Eiq "^x-agent-preview-name: ${expected_service}[[:space:]]*$" "$headers"; }; then
      rm -f "$headers"
      return 0
    fi
    rm -f "$headers"
    sleep 2
  done
  return 1
}

verify_preview() {
  local name="${1:-}"
  validate_name "$name"
  require_command curl
  router_ready
  assert_service_owned_or_absent "$name"
  local id
  id="$(managed_container_id "$name")"
  verify_contract "$name" "$id"
  docker restart "$id" >/dev/null
  wait_for_preview "$name" "$id" ||
    fail "preview did not return its expected direct 2xx response: $(preview_url "$name")"
  printf 'ok %s after restart\n' "$(preview_url "$name")"
}

hub_url() {
  printf 'https://preview-hub.%s\n' "$(tailnet_suffix)"
}

check_hub_credentials() {
  local hub_id_file hub_secret_file hub_id router_id token_response scopes
  hub_id_file="$(credential_path tailscale_hub_oauth_client_id)"
  hub_secret_file="$(credential_path tailscale_hub_oauth_client_secret)"
  check_credential_file "$hub_id_file"
  check_credential_file "$hub_secret_file"
  hub_id="$(tr -d '\r\n' < "$hub_id_file")"
  router_id="$(oauth_client_id)"
  [[ "$hub_id" != "$router_id" ]] ||
    fail "Preview Hub must use a separate read-only OAuth client"

  token_response="$(
    printf 'grant_type=client_credentials&client_id=%s&client_secret=%s' \
      "$(printf '%s' "$hub_id" | jq -sRr @uri)" \
      "$(tr -d '\r\n' < "$hub_secret_file" | jq -sRr @uri)" |
      curl --fail --silent --show-error --max-time 15 \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data-binary @- https://api.tailscale.com/api/v2/oauth/token
  )"
  scopes="$(printf '%s' "$token_response" | jq -er '.scope | split(" ") | sort | join(" ")')"
  [[ "$scopes" == 'devices:core:read services:read' ]] ||
    fail "Preview Hub OAuth client must have exactly Devices Core: Read and Services: Read"
}

hub_container_id() {
  docker ps -aq --filter 'name=^/agent-preview-hub$' | head -n 1
}

wait_for_hub() {
  local deadline url code payload
  deadline=$((SECONDS + 180))
  url="$(hub_url)"
  while (( SECONDS < deadline )); do
    code="$(curl --silent --show-error --max-time 6 --output /dev/null \
      --write-out '%{http_code}' "$url" || true)"
    if [[ "$code" == 200 ]]; then
      payload="$(curl --fail --silent --show-error --max-time 12 "$url/api/previews" || true)"
      if jq -e '.counts and (.machines | type == "array")' <<<"$payload" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 2
  done
  return 1
}

hub_up() {
  require_command docker
  require_command curl
  require_command jq
  stage_runtime_bundle
  router_ready
  check_hub_credentials
  assert_service_owned_or_absent hub

  local existing_id description host_uid host_gid proxy_ip canonical next previous next_id
  canonical=agent-preview-hub
  next="${canonical}-next"
  previous="${canonical}-previous"
  recover_container_replacement "$canonical"
  existing_id="$(hub_container_id)"
  [[ -z "$existing_id" ]] || assert_managed "$existing_id"
  description="$(service_comment hub "Preview Hub")"
  host_uid="$(id -u)"
  host_gid="$(id -g)"
  proxy_ip="$(control_proxy_ip)"

  if ! docker run -d \
    --name "$next" \
    --restart unless-stopped \
    --network "$CONTROL_NETWORK_NAME" \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=16m \
    --user "$host_uid:$host_gid" \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --env PYTHONDONTWRITEBYTECODE=1 \
    --env PYTHONUNBUFFERED=1 \
    --env "PREVIEW_HUB_TAILNET_SUFFIX=$(tailnet_suffix)" \
    --env "PREVIEW_HUB_TAILNET_PROXY=http://$proxy_ip:1055" \
    --label "$OWNERSHIP_LABEL" \
    --label dev.studiomoser.agent-preview.kind=hub \
    --label 'dev.studiomoser.agent-preview.project=Preview Hub' \
    --label docktail.service.enable=true \
    --label docktail.service.name=preview-hub \
    --label "docktail.service.description=$description" \
    --label docktail.service.port=8080 \
    --label docktail.service.service-port=443 \
    --label "docktail.service.network=$CONTROL_NETWORK_NAME" \
    --label docktail.tags=tag:agent-preview \
    --health-cmd "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=3)\"" \
    --health-interval 10s \
    --health-timeout 5s \
    --health-retries 12 \
    --health-start-period 5s \
    --mount "type=bind,source=$HUB_APP,target=/app,readonly" \
    --mount "type=bind,source=$(credential_path tailscale_hub_oauth_client_id),target=/run/secrets/hub/tailscale_hub_oauth_client_id,readonly" \
    --mount "type=bind,source=$(credential_path tailscale_hub_oauth_client_secret),target=/run/secrets/hub/tailscale_hub_oauth_client_secret,readonly" \
    "$HUB_IMAGE" python /app/Preview_Hub.py >/dev/null; then
    fail "could not start replacement Preview Hub; existing hub was preserved"
  fi

  next_id="$(container_id_by_name "$next")"
  if ! wait_for_healthy_container "$next_id"; then
    docker rm -f "$next_id" >/dev/null
    fail "replacement Preview Hub failed its direct health check; existing hub was preserved"
  fi

  begin_container_cutover "$canonical"
  if [[ -n "$existing_id" ]]; then
    docker rename "$canonical" "$previous"
    docker stop "$previous" >/dev/null
  fi
  docker rename "$next" "$canonical"
  end_container_cutover

  if ! wait_for_hub; then
    rollback_container_replacement "$canonical"
    fail "replacement Preview Hub failed its tailnet check; previous hub was restored"
  fi
  [[ -z "$existing_id" ]] || docker rm -f "$previous" >/dev/null
  printf '%s\n' "$(hub_url)"
}

hub_down() {
  require_command docker
  local id
  id="$(hub_container_id)"
  [[ -n "$id" ]] || fail "Preview Hub is not installed"
  assert_managed "$id"
  docker rm -f "$id" >/dev/null
  printf 'removed agent-preview-hub\n'
}

hub_status() {
  require_command docker
  docker ps -a --filter 'name=^/agent-preview-hub$' \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}'
}

hub_verify() {
  require_command docker
  require_command curl
  require_command jq
  stage_runtime_bundle
  check_hub_credentials
  local id restart published kind expected_user app_source client_id_source client_secret_source
  id="$(hub_container_id)"
  [[ -n "$id" ]] || fail "Preview Hub is not installed"
  assert_managed "$id"
  kind="$(docker inspect --format '{{ index .Config.Labels "dev.studiomoser.agent-preview.kind" }}' "$id")"
  [[ "$kind" == hub ]] || fail "Preview Hub kind label is invalid"
  restart="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$id")"
  [[ "$restart" == unless-stopped ]] || fail "Preview Hub restart policy is invalid"
  published="$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$id")"
  [[ "$published" == null || "$published" == '{}' ]] || fail "Preview Hub publishes a host port"
  expected_user="$(id -u):$(id -g)"
  app_source="$HUB_APP"
  client_id_source="$(credential_path tailscale_hub_oauth_client_id)"
  client_secret_source="$(credential_path tailscale_hub_oauth_client_secret)"
  docker inspect "$id" | jq -e \
    --arg user "$expected_user" \
    --arg network "$CONTROL_NETWORK_NAME" \
    --arg app_source "$app_source" \
    --arg client_id_source "$client_id_source" \
    --arg client_secret_source "$client_secret_source" '
    .[0] as $container |
    ($container.Mounts | map({key: .Destination, value: {source: .Source, rw: .RW}}) | from_entries) as $mounts |
    $container.Config.User == $user and
    $container.HostConfig.ReadonlyRootfs == true and
    ($container.HostConfig.CapDrop | index("ALL") != null) and
    ($container.HostConfig.SecurityOpt | index("no-new-privileges:true") != null) and
    ($container.NetworkSettings.Networks | keys == [$network]) and
    ([ $container.Mounts[].Destination ] | sort == [
      "/app",
      "/run/secrets/hub/tailscale_hub_oauth_client_id",
      "/run/secrets/hub/tailscale_hub_oauth_client_secret"
    ]) and
    ($mounts["/app"] == {source: $app_source, rw: false}) and
    ($mounts["/run/secrets/hub/tailscale_hub_oauth_client_id"] == {source: $client_id_source, rw: false}) and
    ($mounts["/run/secrets/hub/tailscale_hub_oauth_client_secret"] == {source: $client_secret_source, rw: false}) and
    ([ $container.Mounts[].Destination ] | index("/var/run/docker.sock") == null)
  ' >/dev/null || fail "Preview Hub container security contract is invalid"
  docker restart "$id" >/dev/null
  wait_for_hub || fail "Preview Hub did not become ready after restart: $(hub_url)"
  printf 'ok %s after restart\n' "$(hub_url)"
}

doctor() {
  local failed=0
  for command_name in docker tailscale jq curl; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf 'ok command %s\n' "$command_name"
    else
      printf 'fail command %s\n' "$command_name"
      failed=1
    fi
  done

  if docker info >/dev/null 2>&1; then
    printf 'ok docker daemon\n'
  else
    printf 'fail docker daemon\n'
    failed=1
  fi

  if tailscale status >/dev/null 2>&1; then
    printf 'ok tailscale client\n'
  else
    printf 'fail tailscale client\n'
    failed=1
  fi

  for credential in tailscale_oauth_client_id tailscale_oauth_client_secret; do
    local path
    path="$(credential_path "$credential")"
    if [[ -s "$path" ]] && check_credential_file "$path"; then
      printf 'ok credential %s\n' "$credential"
    else
      printf 'fail credential %s\n' "$credential"
      failed=1
    fi
  done

  if docker network inspect "$CONTROL_NETWORK_NAME" >/dev/null 2>&1; then
    printf 'ok network %s\n' "$CONTROL_NETWORK_NAME"
  else
    printf 'fail network %s\n' "$CONTROL_NETWORK_NAME"
    failed=1
  fi

  for container in agent-preview-tailscale agent-preview-docktail; do
    local state
    state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    if [[ "$state" == "healthy" ]]; then
      printf 'ok container %s\n' "$container"
    else
      printf 'fail container %s (%s)\n' "$container" "${state:-missing}"
      failed=1
    fi
  done

  return "$failed"
}

main() {
  local command="${1:-}"
  shift || true
  case "$command" in
    router-up) router_up "$@" ;;
    router-down) router_down "$@" ;;
    router-status) router_status "$@" ;;
    prepare) prepare_preview "$@" ;;
    up-static) up_static "$@" ;;
    down) down_preview "$@" ;;
    list) list_previews "$@" ;;
    url)
      validate_name "${1:-}"
      preview_url "$1"
      ;;
    verify) verify_preview "$@" ;;
    hub-up) hub_up "$@" ;;
    hub-down) hub_down "$@" ;;
    hub-status) hub_status "$@" ;;
    hub-verify) hub_verify "$@" ;;
    hub-url) hub_url ;;
    logs) router_compose logs --tail=100 -f ;;
    doctor) doctor ;;
    help|-h|--help|'') usage ;;
    *) usage >&2; fail "unknown command: $command" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
