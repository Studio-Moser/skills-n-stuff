#!/usr/bin/env bash
# Temporary private previews: a launchd job on loopback, published with `tailscale serve`.
set -euo pipefail

CONFIG_ROOT="${PREVIEW_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-previews}"
STATE_DIR="$CONFIG_ROOT/previews"
LOG_DIR="$CONFIG_ROOT/logs"
LABEL_PREFIX="com.studiomoser.preview."
PORT_MIN=3500
PORT_MAX=3599
RESERVED_PORT=443 # T3 Code and other tools own the host's default HTTPS entry.

# The sandboxed Tailscale Mac app refuses to serve folders, so static previews need a server.
# Fonts and CSS masks in a sandboxed frame have an opaque origin and are refused without CORS.
STATIC_SERVER='
import functools, http.server, sys
class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()
handler = functools.partial(Handler, directory=sys.argv[2])
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), handler).serve_forever()
'

usage() {
  cat <<'EOF'
Usage: Preview.sh <command> [arguments]

Commands:
  up-static <name> <dir>                  Serve a folder
  up-cmd <name> <dir> <port> -- <cmd...>  Run an app that listens on 127.0.0.1:<port>
  up-port <name> <port> [dir]             Publish something already listening on <port>
  down <name>                             Stop a preview and remove its tailnet entry
  prune [--dry-run]                       Remove previews whose branch merged, whose
                                          folder is gone, or that are no longer running
  list                                    Show every preview, its status, and its URL
  verify <name>                           Require the tailnet URL to answer
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

validate_name() {
  [[ "${1:-}" =~ ^[a-z][a-z0-9-]{0,54}$ ]] || fail "preview name must match ^[a-z][a-z0-9-]{0,54}$"
}

validate_port() {
  [[ "${1:-}" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1024 && 10#$1 <= 65535 )) ||
    fail "port must be a number from 1024 to 65535 (443 is reserved)"
}

state_file() { printf '%s/%s.json\n' "$STATE_DIR" "$1"; }
plist_file() { printf '%s/%s.plist\n' "$STATE_DIR" "$1"; }
log_file() { printf '%s/%s.log\n' "$LOG_DIR" "$1"; }
job_target() { printf 'gui/%s/%s%s\n' "$(id -u)" "$LABEL_PREFIX" "$1"; }
field() { jq -r --arg key "$2" '.[$key]' "$(state_file "$1")"; }

is_listening() { lsof -nP "-iTCP:$1" -sTCP:LISTEN >/dev/null 2>&1; }
job_loaded() { launchctl print "$(job_target "$1")" >/dev/null 2>&1; }
serve_has() { tailscale serve status --json | jq -e --arg port "$1" '(.TCP // {}) | has($port)' >/dev/null; }

tailnet_url() {
  local host
  host="$(tailscale status --json | jq -er '.Self.DNSName | rtrimstr(".") | select(length > 0)')" ||
    fail "could not read this machine's tailnet name; is Tailscale connected?"
  printf 'https://%s:%s\n' "$host" "$1"
}

# Serve entries belong to whichever preview recorded them; anything else is not ours to replace.
claim_port() {
  ! serve_has "$1" || fail "port $1 is already published by something else"
}

free_port() {
  local port
  for ((port = PORT_MIN; port <= PORT_MAX; port++)); do
    if ! serve_has "$port" && ! is_listening "$port"; then
      printf '%s\n' "$port"
      return
    fi
  done
  fail "no free port from $PORT_MIN to $PORT_MAX; run prune or down"
}

start_job() { # start_job <name> <dir> <port> <program> [args...]
  local name="$1" dir="$2" port="$3" arguments arg
  shift 3
  arguments="$(for arg in "$@"; do jq -n --arg arg "$arg" '$arg'; done | jq -s .)"
  jq -n \
    --arg label "$LABEL_PREFIX$name" \
    --arg dir "$dir" \
    --arg log "$(log_file "$name")" \
    --arg path "$PATH" \
    --arg port "$port" \
    --argjson arguments "$arguments" \
    '{
      Label: $label,
      ProgramArguments: $arguments,
      WorkingDirectory: $dir,
      EnvironmentVariables: {PATH: $path, PORT: $port},
      RunAtLoad: true,
      KeepAlive: {SuccessfulExit: false},
      StandardOutPath: $log,
      StandardErrorPath: $log
    }' | plutil -convert xml1 -o "$(plist_file "$name")" -
  launchctl bootstrap "gui/$(id -u)" "$(plist_file "$name")" ||
    fail "launchd refused to start $name; see $(log_file "$name")"
}

publish() { # publish <name> <kind> <dir> <port>
  local name="$1" kind="$2" dir="$3" port="$4" branch url
  branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  url="$(tailnet_url "$port")"
  # Record first, so `down` can clean up if publishing fails.
  jq -n --arg name "$name" --arg kind "$kind" --arg dir "$dir" --arg port "$port" \
    --arg branch "$branch" --arg url "$url" \
    '{name: $name, kind: $kind, dir: $dir, port: $port, branch: $branch, url: $url}' \
    >"$(state_file "$name")"
  tailscale serve --bg "--https=$port" "$port" >/dev/null
  printf 'url: %s\n' "$url"
  [[ "$kind" == port ]] || printf 'logs: %s\n' "$(log_file "$name")"
  printf 'stop: Preview.sh down %s\n' "$name"
}

stop_preview() {
  local name="$1" port
  port="$(field "$name" port)"
  [[ "$(field "$name" kind)" == port ]] || launchctl bootout "$(job_target "$name")" 2>/dev/null || true
  if [[ "$port" != "$RESERVED_PORT" ]] && serve_has "$port"; then
    tailscale serve "--https=$port" off >/dev/null
  fi
  rm -f "$(state_file "$name")" "$(plist_file "$name")"
}

prepare() { # prepare <name>: validate and clear any earlier preview of this name
  validate_name "$1"
  mkdir -p "$STATE_DIR" "$LOG_DIR"
  chmod 700 "$CONFIG_ROOT" "$STATE_DIR" "$LOG_DIR"
  [[ ! -f "$(state_file "$1")" ]] || stop_preview "$1"
}

resolve_dir() {
  [[ -d "$1" ]] || fail "folder not found: $1"
  (CDPATH= cd -- "$1" && pwd -P)
}

up_static() {
  [[ $# -eq 2 ]] || fail "usage: up-static <name> <dir>"
  local name="$1" dir port python earlier=""
  validate_name "$name"
  dir="$(resolve_dir "$2")"
  require_command python3
  python="$(command -v python3)"
  [[ ! -f "$(state_file "$name")" ]] || earlier="$(field "$name" port)"
  prepare "$name"
  port="${earlier:-$(free_port)}"
  start_job "$name" "$dir" "$port" "$python" -c "$STATIC_SERVER" "$port" "$dir"
  publish "$name" static "$dir" "$port"
}

up_cmd() {
  [[ $# -ge 5 && "$4" == "--" ]] || fail "usage: up-cmd <name> <dir> <port> -- <command...>"
  local name="$1" dir="$2" port="$3" program
  shift 4
  validate_name "$name"
  validate_port "$port"
  dir="$(resolve_dir "$dir")"
  program="$(command -v -- "$1")" && [[ "$program" == /* ]] ||
    fail "program not found: $1; wrap shell syntax with: sh -c '...'"
  shift
  prepare "$name"
  claim_port "$port"
  start_job "$name" "$dir" "$port" "$program" "$@"
  publish "$name" cmd "$dir" "$port"
}

up_port() {
  [[ $# -ge 2 && $# -le 3 ]] || fail "usage: up-port <name> <port> [dir]"
  local name="$1" port="$2" dir
  validate_name "$name"
  validate_port "$port"
  dir="$(resolve_dir "${3:-$PWD}")"
  is_listening "$port" || fail "nothing is listening on port $port"
  prepare "$name"
  claim_port "$port"
  publish "$name" port "$dir" "$port"
}

down() {
  [[ $# -eq 1 ]] || fail "usage: down <name>"
  validate_name "$1"
  [[ -f "$(state_file "$1")" ]] || fail "no preview named $1"
  stop_preview "$1"
  printf 'stopped %s\n' "$1"
}

status_of() {
  local name="$1"
  if is_listening "$(field "$name" port)"; then
    printf 'live\n'
  elif [[ "$(field "$name" kind)" != port ]] && job_loaded "$name"; then
    printf 'starting\n'
  else
    printf 'dead\n'
  fi
}

# Merged means a merged PR whose head is the branch's current tip, which also proves squash merges.
# An ancestor check would wrongly call a new branch with no commits merged.
branch_merged() {
  local dir="$1" branch="$2" heads tip
  [[ -n "$branch" ]] || return 1
  heads="$(cd "$dir" && gh pr list --head "$branch" --state merged --json headRefOid -q '.[].headRefOid' 2>/dev/null)" || {
    printf 'warning: could not check GitHub for %s; keeping its preview\n' "$branch" >&2
    return 1
  }
  [[ -n "$heads" ]] || return 1
  tip="$(git -C "$dir" rev-parse -q --verify "refs/heads/$branch")" || return 0
  grep -Fxq "$tip" <<<"$heads"
}

prune_reason() {
  local name="$1" dir
  dir="$(field "$name" dir)"
  if [[ ! -d "$dir" ]]; then
    printf 'source folder is gone\n'
  elif [[ "$(status_of "$name")" == dead ]]; then
    printf 'not running\n'
  elif branch_merged "$dir" "$(field "$name" branch)"; then
    printf 'branch %s merged\n' "$(field "$name" branch)"
  fi
}

each_preview() {
  local file
  [[ -d "$STATE_DIR" ]] || return 0
  for file in "$STATE_DIR"/*.json; do
    [[ -e "$file" ]] || continue
    basename "$file" .json
  done
}

prune() {
  [[ $# -eq 0 || "${1:-}" == "--dry-run" ]] || fail "usage: prune [--dry-run]"
  local name reason
  while read -r name; do
    reason="$(prune_reason "$name")"
    [[ -n "$reason" ]] || continue
    printf '%s\t%s\n' "$name" "$reason"
    [[ $# -eq 1 ]] || stop_preview "$name"
  done < <(each_preview)
}

list() {
  local name
  while read -r name; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$(status_of "$name")" "$(field "$name" url)" \
      "$(field "$name" dir)" "$(field "$name" branch)"
  done < <(each_preview)
}

verify() {
  [[ $# -eq 1 ]] || fail "usage: verify <name>"
  validate_name "$1"
  [[ -f "$(state_file "$1")" ]] || fail "no preview named $1"
  local url port try tries="${PREVIEW_VERIFY_TRIES:-60}"
  url="$(field "$1" url)"
  port="$(field "$1" port)"
  for ((try = 1; try <= tries; try++)); do
    if curl --fail --silent --show-error --max-time 10 --output /dev/null "$url" 2>/dev/null; then
      if lsof -nP "-iTCP:$port" -sTCP:LISTEN 2>/dev/null | grep -Eq "(\*|0\.0\.0\.0|\[::\]):$port"; then
        printf 'warning: port %s also listens beyond loopback, so your local network can reach it\n' "$port"
      fi
      printf 'ok: %s\n' "$url"
      return 0
    fi
    (( try == tries )) || sleep 1
  done
  fail "$url did not answer; see $(log_file "$1")"
}

main() {
  local command="${1:-}"
  [[ $# -eq 0 ]] || shift
  case "$command" in
    -h | --help | help | "")
      usage
      return
      ;;
  esac
  require_command tailscale
  require_command jq
  case "$command" in
    up-static) up_static "$@" ;;
    up-cmd) up_cmd "$@" ;;
    up-port) up_port "$@" ;;
    down) down "$@" ;;
    prune) prune "$@" ;;
    list) list "$@" ;;
    verify) verify "$@" ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
