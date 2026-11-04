#!/usr/bin/env bash
# Exercises every Preview.sh command against fake tailscale, launchctl, lsof, curl, and gh.
set -euo pipefail

plugin_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
controller="$plugin_root/skills/serve-preview/scripts/Preview.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fake="$test_root/bin"
calls="$test_root/calls"
serve="$test_root/serve"       # one "port" per line: the fake serve config
listening="$test_root/listening" # one "port" or "port wildcard" per line
loaded="$test_root/loaded"     # one launchd label per line
mkdir -p "$fake"
: >"$calls"; : >"$listening"; : >"$loaded"
printf '443\n' >"$serve" # T3 Code's own entry

cat >"$fake/tailscale" <<'EOF'
#!/usr/bin/env bash
printf 'tailscale %s\n' "$*" >>"$PREVIEW_TEST_CALLS"
if [ "$1 $2" = "serve status" ]; then
  jq -Rn '{TCP: ([inputs | {(.): {}}] | add // {})}' <"$PREVIEW_TEST_SERVE"
elif [ "$1" = "status" ]; then
  printf '{"Self":{"DNSName":"mac.tail.ts.net."}}\n'
elif [ "$1 $2" = "serve --bg" ]; then
  printf '%s\n' "${3#--https=}" >>"$PREVIEW_TEST_SERVE"
elif [ "$1" = "serve" ] && [ "$3" = "off" ]; then
  port="${2#--https=}"
  grep -vFx "$port" "$PREVIEW_TEST_SERVE" >"$PREVIEW_TEST_SERVE.new" || true
  mv "$PREVIEW_TEST_SERVE.new" "$PREVIEW_TEST_SERVE"
fi
EOF

cat >"$fake/launchctl" <<'EOF'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >>"$PREVIEW_TEST_CALLS"
case "$1" in
  bootstrap)
    /usr/libexec/PlistBuddy -c 'Print :Label' "$3" >>"$PREVIEW_TEST_LOADED"
    ;;
  bootout)
    label="${2##*/}"
    grep -vFx "$label" "$PREVIEW_TEST_LOADED" >"$PREVIEW_TEST_LOADED.new" || true
    mv "$PREVIEW_TEST_LOADED.new" "$PREVIEW_TEST_LOADED"
    ;;
  print)
    grep -qFx "${2##*/}" "$PREVIEW_TEST_LOADED"
    ;;
esac
EOF

cat >"$fake/lsof" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in -iTCP:*) port="${arg#-iTCP:}" ;; esac
done
if grep -qFx "$port wildcard" "$PREVIEW_TEST_LISTENING"; then
  printf 'COMMAND PID NAME\nnode 1 *:%s (LISTEN)\n' "$port"
elif grep -qFx "$port" "$PREVIEW_TEST_LISTENING"; then
  printf 'COMMAND PID NAME\nnode 1 127.0.0.1:%s (LISTEN)\n' "$port"
else
  exit 1
fi
EOF

cat >"$fake/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$PREVIEW_TEST_CALLS"
[ "${PREVIEW_TEST_CURL_FAILS:-}" != 1 ]
EOF

cat >"$fake/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$PREVIEW_TEST_CALLS"
[ "${PREVIEW_TEST_GH_FAILS:-}" != 1 ] || exit 1
printf '%s\n' "${PREVIEW_TEST_MERGED_HEADS:-}"
EOF
chmod +x "$fake"/*

export PATH="$fake:$PATH"
export PREVIEW_CONFIG_DIR="$test_root/config"
export PREVIEW_VERIFY_TRIES=1
export PREVIEW_TEST_CALLS="$calls" PREVIEW_TEST_SERVE="$serve"
export PREVIEW_TEST_LISTENING="$listening" PREVIEW_TEST_LOADED="$loaded"

state="$PREVIEW_CONFIG_DIR/previews"
failures=0

check() { # check <label> <command...>
  local label="$1"; shift
  if "$@"; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label"
    failures=$((failures + 1))
  fi
}
refuses() { ! "$controller" "$@" >/dev/null 2>&1; }
called() { grep -qF -- "$1" "$calls"; }
in_serve() { grep -qFx "$1" "$serve"; }
not() { ! "$@"; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$state/$1.plist"; }
plist_has() { plist "$1" "$2" | grep -qF -- "$3"; }
output_has() { grep -qF -- "$1" "$test_root/output"; }

site="$test_root/My Site & Co"
mkdir -p "$site"

# up-static
"$controller" up-static site-one "$site" >"$test_root/output"
check "up-static prints the tailnet URL" output_has 'https://mac.tail.ts.net:3500'
check "up-static prints the log path" output_has "$PREVIEW_CONFIG_DIR/logs/site-one.log"
check "up-static publishes the port over HTTPS" called 'tailscale serve --bg --https=3500 3500'
check "up-static bootstraps launchd from the config folder" \
  called "launchctl bootstrap gui/$(id -u) $state/site-one.plist"
check "the job file stays out of LaunchAgents, so it ends at reboot" \
  not called 'Library/LaunchAgents'
check "static server binds loopback only" plist_has site-one ProgramArguments '127.0.0.1'
check "a folder with spaces and & reaches the job intact" plist_has site-one ProgramArguments "$site"
check "static responses keep the CORS header" plist_has site-one ProgramArguments 'Access-Control-Allow-Origin'
check "a crash restarts the job, a clean exit does not" \
  plist_has site-one KeepAlive:SuccessfulExit 'false'

# ports
"$controller" up-static site-two "$site" >"$test_root/output"
check "next preview takes the next free port" output_has ':3501'
printf '3502\n' >>"$listening"
printf '3503\n' >>"$serve"
"$controller" up-static site-three "$site" >"$test_root/output"
check "ports already listening or already served are skipped" output_has ':3504'
"$controller" up-static site-two "$site" >"$test_root/output"
check "re-running a name keeps its port" output_has ':3501'

# up-cmd
app="$test_root/app"
mkdir -p "$app"
"$controller" up-cmd app-one "$app" 3600 -- python3 -m http.server 3600 >"$test_root/output"
check "up-cmd resolves the program to an absolute path" \
  plist_has app-one ProgramArguments "$(command -v python3)"
check "up-cmd runs in the project folder" plist_has app-one WorkingDirectory "$app"
check "up-cmd sets PORT" plist_has app-one EnvironmentVariables:PORT '3600'
check "up-cmd publishes its port" called 'tailscale serve --bg --https=3600 3600'
check "up-cmd refuses an unknown program" refuses up-cmd app-two "$app" 3601 -- no-such-program-here

# up-port
: >"$calls"
printf '9080\n' >>"$listening"
"$controller" up-port stack 9080 "$app" >"$test_root/output"
check "up-port publishes the port" called 'tailscale serve --bg --https=9080 9080'
check "up-port starts no launchd job" not called 'launchctl bootstrap'
check "up-port refuses T3 Code's port 443" refuses up-port t3 443 "$app"
check "up-port refuses a port served by something else" refuses up-port other 3503 "$app"
check "up-port refuses a port with nothing listening" refuses up-port idle 9090 "$app"

# validation
check "invalid names are refused" refuses up-static '../evil' "$site"
check "uppercase names are refused" refuses up-static 'Evil' "$site"
check "a missing folder is refused" refuses up-static nope "$test_root/missing"
check "a non-numeric port is refused" refuses up-cmd bad "$app" abc -- python3
check "down of an unknown preview is refused" refuses down nothing-here
check "retired router commands are gone" refuses router-up
check "retired hub commands are gone" refuses hub-up

# list and verify
printf '3500\n' >>"$listening"
"$controller" list >"$test_root/output"
check "list shows a listening preview as live" grep -qE 'site-one[[:space:]]+live[[:space:]]+https://mac.tail.ts.net:3500' "$test_root/output"
check "list shows a loaded job that is not listening as starting" grep -qE 'site-two[[:space:]]+starting' "$test_root/output"

check "verify passes when the URL answers" "$controller" verify site-one
check "verify requests the tailnet URL" called 'https://mac.tail.ts.net:3500'
export PREVIEW_TEST_CURL_FAILS=1
check "verify fails when the URL does not answer" refuses verify site-one
unset PREVIEW_TEST_CURL_FAILS
sed -i '' 's/^3500$/3500 wildcard/' "$listening"
"$controller" verify site-one >"$test_root/output" 2>&1
check "verify warns when a preview also listens beyond loopback" output_has 'beyond loopback'
sed -i '' 's/^3500 wildcard$/3500/' "$listening"

# down
"$controller" down site-three >/dev/null
check "down removes its serve entry" not in_serve 3504
check "down removes its state" not test -e "$state/site-three.json"
check "down removes its job file" not test -e "$state/site-three.plist"
check "down stops the job" not grep -qFx com.studiomoser.preview.site-three "$loaded"
"$controller" down stack >/dev/null
check "down of up-port leaves the listener alone" grep -qFx 9080 "$listening"
check "T3 Code's serve entry survives down" in_serve 443
check "another tool's serve entry survives down" in_serve 3503

# prune
repo="$test_root/repo"
git -c init.defaultBranch=main init -q "$repo"
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
git -C "$repo" checkout -q -b feat/thing
tip="$(git -C "$repo" rev-parse HEAD)"

fresh() { # fresh <name> <folder> <port>: a live, loaded preview
  "$controller" up-cmd "$1" "$2" "$3" -- python3 >/dev/null
  printf '%s\n' "$3" >>"$listening"
}
fresh keeper "$app" 3610
fresh merged "$repo" 3611
mkdir -p "$test_root/doomed"
fresh gone "$test_root/doomed" 3612
rm -rf "$test_root/doomed"
fresh crashed "$app" 3613
grep -vFx com.studiomoser.preview.crashed "$loaded" >"$loaded.new" || true; mv "$loaded.new" "$loaded"
grep -vFx 3613 "$listening" >"$listening.new" || true; mv "$listening.new" "$listening"

export PREVIEW_TEST_MERGED_HEADS="$tip"
"$controller" prune --dry-run >"$test_root/output"
check "prune --dry-run names a merged branch" output_has 'merged'
check "prune --dry-run names a missing folder" output_has 'gone'
check "prune --dry-run names a dead preview" output_has 'crashed'
check "prune --dry-run removes nothing" test -e "$state/merged.json"
check "prune --dry-run keeps the serve entry" in_serve 3611
check "prune --dry-run spares a healthy preview" not grep -q '^keeper' "$test_root/output"

export PREVIEW_TEST_MERGED_HEADS=deadbeef
"$controller" prune --dry-run >"$test_root/output"
check "a merged PR at another head does not count" not grep -q '^merged' "$test_root/output"

unset PREVIEW_TEST_MERGED_HEADS
"$controller" prune --dry-run >"$test_root/output"
check "a branch with no merged PR is kept" not grep -q '^merged' "$test_root/output"

export PREVIEW_TEST_GH_FAILS=1
"$controller" prune --dry-run >"$test_root/output" 2>/dev/null
check "a failed GitHub lookup keeps the preview" not grep -q '^merged' "$test_root/output"
unset PREVIEW_TEST_GH_FAILS

export PREVIEW_TEST_MERGED_HEADS="$tip"
"$controller" prune >/dev/null
check "prune removes the merged preview" not test -e "$state/merged.json"
check "prune removes the merged serve entry" not in_serve 3611
check "prune removes the missing-folder preview" not test -e "$state/gone.json"
check "prune removes the dead preview" not test -e "$state/crashed.json"
check "prune clears the dead preview's serve entry" not in_serve 3613
check "prune keeps the healthy preview" test -e "$state/keeper.json"
check "T3 Code's serve entry survives prune" in_serve 443
check "another tool's serve entry survives prune" in_serve 3503
unset PREVIEW_TEST_MERGED_HEADS

# Hard rule across every call this test made.
check "nothing ever calls Funnel" not grep -qi funnel "$calls"

if [ "$failures" -ne 0 ]; then
  printf '%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all checks passed\n'
