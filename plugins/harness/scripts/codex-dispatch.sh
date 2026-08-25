#!/usr/bin/env bash
# Run the internal Codex adapter with an explicit, enforceable authority ceiling.
set -euo pipefail

usage() {
  printf '%s\n' '{"status":"failed"}'
  exit 2
}

blocked() {
  printf '%s\n' '{"status":"failed"}'
  exit 4
}

operation=
cwd=
sandbox=
approval=
model=
effort=
prompt=
report=
fixed_target=
skip_git_repo_check=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --operation|--cwd|--sandbox|--approval|--model|--effort|--prompt|--report|--fixed-target)
      [ "$#" -ge 2 ] || usage
      key="${1#--}"
      key="${key//-/_}"
      printf -v "$key" '%s' "$2"
      shift 2
      ;;
    --skip-git-repo-check)
      skip_git_repo_check=true
      shift
      ;;
    *) usage ;;
  esac
done

for value in "$operation" "$cwd" "$sandbox" "$approval" "$model" "$effort" "$prompt" "$report"; do
  [ -n "$value" ] || usage
done
[ -d "$cwd" ] || blocked "working directory does not exist"
[ -r "$prompt" ] || blocked "prompt is not readable"

# The App Server turn is non-interactive. An outstanding on-request approval
# cannot be surfaced safely, while `never` denies escalation and returns the
# failure to the worker. The parent must obtain every required approval before
# dispatch.
[ "$approval" = "never" ] || blocked "outstanding approvals cannot be enforced by non-interactive Codex"

case "$operation" in
  execute)
    case "$sandbox" in
      read-only|workspace-write) ;;
      *) blocked "execute sandbox exceeds the supported authority ceiling" ;;
    esac
    ;;
  review)
    [ "$sandbox" = "read-only" ] || blocked "review requires a read-only sandbox"
    [ -n "$fixed_target" ] || blocked "review requires a fixed commit target"
    [ "$skip_git_repo_check" = false ] || blocked "review requires its fixed Git target"
    ;;
  computer-use)
    case "$sandbox" in
      read-only|workspace-write|danger-full-access) ;;
      *) blocked "unsupported computer-use sandbox" ;;
    esac
    ;;
  *) usage ;;
esac

driver="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-app-server.py"
command=(
  "$driver" run
  --codex-bin "${HARNESS_CODEX_BIN:-codex}"
  --operation "$operation"
  --cwd "$cwd"
  --sandbox "$sandbox"
  --approval never
  --model "$model"
  --effort "$effort"
  --prompt "$prompt"
  --report "$report"
)
[ -z "$fixed_target" ] || command+=(--fixed-target "$fixed_target")
[ "$skip_git_repo_check" = false ] || command+=(--skip-git-repo-check)

exec "${command[@]}"
