#!/usr/bin/env bats
#
# Repo-wide guard against a bash 3.2 trap that silently disables assertions.
#
# macOS ships GNU bash 3.2.57 (frozen for licensing reasons), and there `set -e`
# does NOT fire when a bare `[[ ... ]]` evaluates false — unless it is the last
# command to run. POSIX `[ ]` does not have this bug:
#
#   bash -c 'set -e; [[ foo == bar ]]; [[ foo == foo ]]; echo reached'  # prints
#   bash -c 'set -e; [ foo = bar ];   [ foo = foo ];   echo reached'    # silent
#
# A bats @test body is a function whose final exit status decides pass/fail, so
# any `[[ ]]` assertion that is not the last statement is inert: it can never
# fail the test. Measured on this repo before the fix — replacing all 22 such
# assertions with a guaranteed-false one changed nothing, 56 ok / 0 fail.
#
# `|| return 1` forces the status to propagate. This guard also catches the way
# the bug spreads: appending a line under a previously-final assertion silently
# kills it.
#
# Lives in pm's suite because that is the repo's only bats harness; the check
# is repo-wide, matching skill-frontmatter.bats.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "no bare [[ ]] assertion sits in a non-final position without || return 1" {
  run python3 - "$REPO" <<'PY'
import glob, os, re, sys

repo = sys.argv[1]
offenders = []
scanned = 0

for path in sorted(glob.glob(os.path.join(repo, "plugins/*/tests/*.bats"))):
    src = open(path).read()
    rel = os.path.relpath(path, repo)
    for m in re.finditer(r'@test "([^"]+)" \{\n(.*?)\n\}', src, re.S):
        scanned += 1
        name = m.group(1)
        body = m.group(2).split("\n")
        first_line = src[: m.start(2)].count("\n") + 1
        live = [i for i, l in enumerate(body)
                if l.strip() and not l.strip().startswith("#")]
        if not live:
            continue
        last = live[-1]
        for i in live:
            if i == last:
                continue  # final position decides the test's status already
            if re.match(r"^\s*\[\[.*\]\]\s*$", body[i]):
                offenders.append((rel, first_line + i, name, body[i].strip()))

for rel, line, name, text in offenders:
    print(f"{rel}:{line}  in @test {name!r}")
    print(f"    {text}")
    print("    ^ not the last statement; add '|| return 1' or it cannot fail the test")
print(f"scanned={scanned} tests offenders={len(offenders)}")
sys.exit(1 if offenders else 0)
PY
  [ "$status" -eq 0 ]
}
