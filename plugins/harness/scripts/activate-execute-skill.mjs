#!/usr/bin/env node

import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

function isExplicitExecute(prompt) {
  if (typeof prompt !== "string") return false;

  const normalized = prompt.toLowerCase().trim().split(/\s+/).join(" ");
  const padded = ` ${normalized} `;
  const requestMarker = [
    "harnessrequest",
    "harness request",
    "routing_request",
  ].some((marker) => normalized.includes(marker));
  const resultMarker = ["harnessresult", "harness result"].some((marker) =>
    normalized.includes(marker),
  );
  const actionMarker = [
    " complete ",
    " construct ",
    " execute ",
    " produce ",
    " requires ",
    " return ",
    " write ",
  ].some((marker) => padded.includes(marker));

  return (requestMarker || resultMarker) && actionMarker;
}

function activationContext(skill, contract) {
  const adapterMarker = "### Internal Codex adapter";
  const verificationMarker = "## Verify and return";
  const [beforeAdapter, afterAdapter] = skill.split(adapterMarker);
  const [, verification] = afterAdapter.split(verificationMarker);

  const contractStart = "For a blocked pre-dispatch terminal result";
  const contractEnd = "\n\n`artifacts.files`";
  const blockedContract = contract.slice(
    contract.indexOf(contractStart),
    contract.indexOf(contractEnd, contract.indexOf(contractStart)),
  );

  return (
    "Detected environment state: this is an explicit Harness execute contract. " +
    "/harness:execute is already loaded for this turn; invoking the Skill tool " +
    "again would duplicate context. The installed procedure below governs the " +
    "task before any other task action.\n\n" +
    beforeAdapter +
    adapterMarker +
    "\n\nThe non-native Codex adapter details are intentionally not preloaded. That " +
    "path requires loading the full /harness:execute skill before dispatch.\n\n" +
    verificationMarker +
    verification +
    "\n\nRequired Harness contract excerpt:\n\n" +
    blockedContract
  );
}

function main() {
  let event;
  try {
    event = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return;
  }

  if (
    event?.hook_event_name !== "UserPromptSubmit" ||
    !isExplicitExecute(event.prompt)
  ) {
    return;
  }

  try {
    const pluginRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
    const skill = readFileSync(
      resolve(pluginRoot, "skills", "execute", "SKILL.md"),
      "utf8",
    );
    const contract = readFileSync(
      resolve(pluginRoot, "references", "harness-contract.md"),
      "utf8",
    );
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: activationContext(skill, contract),
        },
      }),
    );
  } catch {
    return;
  }
}

main();
