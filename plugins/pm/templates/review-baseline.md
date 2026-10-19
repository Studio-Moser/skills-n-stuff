# Review Contract

Review the requested fixed target against the approved requirements and the repository's
current behavior. A reviewer report is a claim until its decisive checks are reproduced.

## Review axes

Report each applicable axis separately:

- **Quality:** correctness, regressions, security, edge cases, error handling,
  performance, maintainability, and adequate tests.
- **Spec Fidelity:** missing or partial requirements, unrequested behavior, and
  implementations that do not match the approved requirement. State when no approved
  specification exists.
- **Blast Radius:** persisted data or migrations; public APIs, protocols, wire formats,
  or serialization; authentication, authorization, permissions, or another security
  boundary; and shared runtime, dependency, build, deployment, or configuration
  behavior. Name the central safety assumption and require proof aimed at it.

## Findings

A blocking finding must include:

- Severity.
- File and line or the narrowest available location.
- Trigger or execution path.
- Concrete failure mode and consequence.
- Evidence that the reviewed change introduced or exposed it.
- Fix direction or the proof needed to dispute it.

Block on actionable correctness, security, specification, or blast-radius failures.
Report a severe concern without enough proof as an unresolved risk. Do not present it
as a proven defect. Omit optional cleanup, style preferences, and speculative
maintainability suggestions unless the approved task requires them. Mark a verified
pre-existing issue separately from a regression in the reviewed target.

If nothing actionable remains, state `No findings` explicitly.

## Rereview convergence

The first pass reviews the full fixed target. A later pass reviews the remediation
delta and affected behavior while retaining unresolved earlier blockers. Do not repeat
a disposed finding without new evidence. Report every observed instance of one bug
class together. Stop when neither the target nor a relevant risk changed. Reaching a
round limit reports residual blockers; it never authorizes merging over them.

## Evidence and recovery

Use the repository's named Testing Seam and required checks. A skipped check, zero
relevant cases, stale result, or successful process without the expected positive
signal is unproven. Treat rollback as part of blast radius: state when reverting code
cannot reverse data, protocol, or external-system effects.
