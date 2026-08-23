#!/usr/bin/env bash
# Run the internal Codex adapter with an explicit, enforceable authority ceiling.
set -euo pipefail

usage() {
  echo "usage: codex-dispatch.sh --operation execute|review|computer-use --cwd DIR --sandbox MODE --approval never --model MODEL --effort EFFORT --prompt FILE --report FILE [--fixed-target SHA] [--skip-git-repo-check]" >&2
  exit 2
}

blocked() {
  echo "BLOCKED: $1" >&2
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

# Codex exec is non-interactive. An outstanding on-request approval cannot be
# surfaced safely, while `never` denies escalation and returns the failure to the
# worker. The parent must obtain every required approval before dispatch.
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

codex_bin="${HARNESS_CODEX_BIN:-codex}"
if [[ "$codex_bin" == */* ]]; then
  [ -x "$codex_bin" ] || blocked "Codex executable is unavailable"
else
  command -v "$codex_bin" >/dev/null 2>&1 || blocked "Codex executable is unavailable"
fi

command=(
  "$codex_bin"
  -C "$cwd"
  -s "$sandbox"
  -a never
  -m "$model"
  -c "model_reasoning_effort=$effort"
)
case "$operation" in
  execute|computer-use)
    command+=(exec)
    if [ "$skip_git_repo_check" = true ]; then
      command+=(--skip-git-repo-check)
    fi
    command+=(-)
    ;;
  review)
    command+=(review --commit "$fixed_target" -)
    ;;
esac

"${command[@]}" < "$prompt" > "$report"
