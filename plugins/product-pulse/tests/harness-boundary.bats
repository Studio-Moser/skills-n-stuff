#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "Product Pulse contains no Harness control-plane implementation" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "plugins" / "product-pulse"
literal_forbidden = (
    "model-rubric.yml",
    "model@effort",
    "via:",
    "codex-implementation",
    "codex-review",
    "codex-computer-use",
    "command -v codex",
    "model-selection rubric",
    "cheap, capable model",
    "strong model",
    "pass `model`",
    "Agent tool calls",
)
regex_forbidden = (
    re.compile(r"^\s*model\s*:", re.MULTILINE | re.IGNORECASE),
    re.compile(r"^\s*effort\s*:", re.MULTILINE | re.IGNORECASE),
    re.compile(r"\b(?:sonnet|opus|haiku|gpt-[\w.-]+)\b", re.IGNORECASE),
    re.compile(r"\bdispatch(?:es|ed|ing)?\s+(?:\w+\s+){0,3}(?:sub-?agents?|agents?)\b", re.IGNORECASE),
)
hits = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or "tests" in path.relative_to(root).parts:
        continue
    text = path.read_text(errors="ignore")
    for needle in literal_forbidden:
        if needle.lower() in text.lower():
            hits.append(f"{path.relative_to(root)}: {needle}")
    for pattern in regex_forbidden:
        if pattern.search(text):
            hits.append(f"{path.relative_to(root)}: /{pattern.pattern}/")

assert not hits, "Product Pulse owns Harness control-plane behavior:\n" + "\n".join(hits)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "Product Pulse workflows submit semantic Harness routes" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "plugins" / "product-pulse" / "skills"

def packets(name):
    text = (root / name / "SKILL.md").read_text()
    return re.findall(r"```yaml\n(operation: .*?)\n```", text, re.DOTALL), text

expected = {
    "daily-research": (("execute", "bulk"), ("execute", "taste")),
    "weekly-strategist": (("execute", "bulk"), ("execute", "taste"), ("review", "review")),
    "deep-dive": (("execute", "bulk"), ("execute", "taste"), ("review", "review")),
}
failures = []
for name, required in expected.items():
    values, text = packets(name)
    routes = {
        (operation.group(1), route.group(1))
        for packet in values
        if (operation := re.search(r"^operation:\s*(\S+)", packet, re.MULTILINE))
        and (route := re.search(r"^route:\s*(\S+)", packet, re.MULTILINE))
    }
    for pair in required:
        if pair not in routes:
            failures.append(f"{name}: missing operation/route {pair[0]}/{pair[1]}")
    for packet in values:
        for field in ("outcome:", "context:", "authority:", "constraints:", "verification:"):
            if field not in packet:
                failures.append(f"{name}: packet omits {field}")
    if "Harness Result" not in text or "evidence.outcome" not in text:
        failures.append(f"{name}: does not validate the Harness Result evidence")

setup_text = (root / "setup" / "SKILL.md").read_text()
for phrase in (
    "Invoke `harness:setup` with `mode: status`",
    "Run `/harness:setup`, then rerun `/product-pulse:setup`.",
):
    if phrase not in setup_text:
        failures.append(f"setup: missing {phrase}")
if re.search(r"```yaml\noperation:", setup_text):
    failures.append("setup: reproduces Harness setup request mechanics")

assert not failures, "invalid Product Pulse Harness routes:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "fresh Harness packets embed Product Pulse research constraints" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "plugins" / "product-pulse" / "skills"

def route_packet(name, operation, route):
    text = (root / name / "SKILL.md").read_text()
    packets = re.findall(r"```yaml\n(operation: .*?)\n```", text, re.DOTALL)
    for packet in packets:
        if f"operation: {operation}" in packet and f"route: {route}" in packet:
            return " ".join(packet.split()).lower()
    return ""

requirements = {
    ("daily-research", "execute", "bulk"): (
        "every always check search term", "max 5 findings", "real source url",
        "source credibility", "dedup list", "weekly strategic direction",
        "title, url, summary, impact, effort, confidence, and relevance",
    ),
    ("daily-research", "execute", "taste"): (
        "always-check hit", "deduplicate across domains", "strategic filter",
        "source performance", "search terms used", "report path",
    ),
    ("weekly-strategist", "execute", "bulk"): (
        "market scout", "competitor tracker", "audience analyst", "growth analyst",
        "product scout", "source url", "so what", "max 500 words",
    ),
    ("weekly-strategist", "execute", "taste"): (
        "exactly 3", "tied to evidence", "corroborate", "strategy brief",
        "recommendations", "{week_dir}/{yyyy}-w{nn}-strategy-brief.md",
        "{week_dir}/{yyyy}-w{nn}-recommendations.md",
    ),
    ("deep-dive", "execute", "bulk"): (
        "full source content", "author", "publication date", "credibility",
        "citation url", "project comparison", "do not fabricate",
    ),
    ("deep-dive", "execute", "taste"): (
        "synthesize", "project comparison", "actionable recommendations",
        "citations", "report path",
    ),
}

failures = []
for key, phrases in requirements.items():
    packet = route_packet(*key)
    if not packet:
        failures.append(f"{key[0]}: no {key[1]}/{key[2]} packet")
        continue
    for phrase in phrases:
        if phrase.lower() not in packet:
            failures.append(f"{key[0]} {key[2]} packet omits: {phrase}")
    for private_path in ("plugins/product-pulse/", "agents/market-scout.md", "references/report-template.md"):
        if private_path in packet:
            failures.append(f"{key[0]} {key[2]} packet leaks private instruction: {private_path}")

for name in ("weekly-strategist", "deep-dive"):
    review = route_packet(name, "review", "review")
    for phrase in ("contradictory", "high-impact", "fixed_target", "credibility", "citations"):
        if phrase not in review:
            failures.append(f"{name} review packet omits: {phrase}")

assert not failures, "non-self-contained Product Pulse packets:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "weekly adjudicates contested evidence before strategy synthesis" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

text = (Path(sys.argv[1]) / "plugins/product-pulse/skills/weekly-strategist/SKILL.md").read_text()
packets = [
    (match.start(), match.group(1))
    for match in re.finditer(r"```yaml\n(operation: .*?)\n```", text, re.DOTALL)
]
review = [position for position, packet in packets if "operation: review" in packet and "route: review" in packet]
taste = [(position, packet) for position, packet in packets if "operation: execute" in packet and "route: taste" in packet]
failures = []
if len(review) != 1:
    failures.append(f"expected one review packet, found {len(review)}")
if len(taste) != 1:
    failures.append(f"expected one taste packet, found {len(taste)}")
if len(review) == 1 and len(taste) == 1:
    if review[0] > taste[0][0]:
        failures.append("taste synthesis precedes evidence adjudication")
    normalized = " ".join(taste[0][1].split()).lower()
    if "accepted adjudications" not in normalized:
        failures.append("taste synthesis does not consume accepted adjudications")

assert not failures, "invalid weekly evidence flow:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "deep-dive audits the project before comparison requests" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

text = (Path(sys.argv[1]) / "plugins/product-pulse/skills/deep-dive/SKILL.md").read_text()
audit_match = re.search(r"^## Phase \d+: Audit the Current Project$", text, re.MULTILINE)
audit = audit_match.start() if audit_match else -1
packets = [
    (match.start(), match.group(1))
    for match in re.finditer(r"```yaml\n(operation: .*?)\n```", text, re.DOTALL)
]
comparisons = [
    (position, packet)
    for position, packet in packets
    if "operation: execute" in packet
    and "route: bulk" in packet
    and "project comparison" in packet.lower()
]
failures = []
if audit < 0:
    failures.append("missing project-audit phase")
if not comparisons:
    failures.append("no bulk project-comparison packet")
for position, packet in comparisons:
    if audit > position:
        failures.append("project comparison request precedes project audit")
    normalized = " ".join(packet.split()).lower()
    for required in ("current project facts", "repository-relative project files"):
        if required not in normalized:
            failures.append(f"comparison packet omits audited input: {required}")

assert not failures, "invalid deep-dive comparison flow:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "Product Pulse keeps report and publication ownership" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "plugins" / "product-pulse"
contracts = {
    "daily": (
        root / "skills/daily-research/SKILL.md",
        ("{week_dir}/{today}-daily-research.md", "Source Performance", "gh pr create", "auto_merge"),
    ),
    "weekly": (
        root / "skills/weekly-strategist/SKILL.md",
        ("{week_dir}/{YYYY}-W{NN}-strategy-brief.md", "{week_dir}/{YYYY}-W{NN}-recommendations.md", "gh pr create", "auto_merge"),
    ),
    "deep-dive": (
        root / "skills/deep-dive/SKILL.md",
        ("{research_dir}/deep-dives/", "## Sources", "gh pr create", "auto_merge"),
    ),
}
failures = []
for name, (path, phrases) in contracts.items():
    text = path.read_text()
    for phrase in phrases:
        if phrase not in text:
            failures.append(f"{name}: missing publication contract {phrase}")

readme = (root / "README.md").read_text().lower()
for phrase in (
    "product pulse owns research questions, source selection, credibility checks, citations, project comparison, synthesis, and report publication",
    "harness owns concrete routing, execution, and evidence mechanics",
):
    if phrase not in readme:
        failures.append(f"README: missing ownership statement {phrase}")

assert not failures, "Product Pulse publication boundary regressed:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
