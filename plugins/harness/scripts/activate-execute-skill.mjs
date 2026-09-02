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
  const actionStart = "Before the first call to an environment-provided action";
  const actionEnd = "\n\nUse Shelby only when callable";
  const actionContract = skill.slice(
    skill.indexOf(actionStart),
    skill.indexOf(actionEnd, skill.indexOf(actionStart)),
  );
  const resultStart = "Return every field in the HarnessResult";
  const resultFields = skill.slice(skill.indexOf(resultStart)).trim();
  const contractStart = "For a blocked pre-dispatch terminal result";
  const contractEnd = "\n\n`artifacts.files`";
  const blockedContract = contract.slice(
    contract.indexOf(contractStart),
    contract.indexOf(contractEnd, contract.indexOf(contractStart)),
  );

  return [
    "Detected environment state: this is an explicit Harness execute contract.",
    "Follow this order:",
    "1. **Request** — Read and validate the request and its authority ceiling.",
    "2. **Action contract** — Read its public contract or schema before the first operational call. Use the documented action name and payload shape on the first attempt.",
    "3. **Action result** — When a structured response includes `check`, copy its exact `check` value to the beginning of `evidence.checks`; append bounded provenance only afterward.",
    "4. **Terminal result** — Write every HarnessResult field using the installed blocked-result encoding when preflight cannot proceed.",
    "5. **Dispatch** — If preflight succeeds and route selection or dispatch is needed, invoke the full `/harness:execute` skill before continuing.",
    "Installed excerpts:",
    actionContract,
    blockedContract,
    resultFields,
  ].join("\n\n");
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
