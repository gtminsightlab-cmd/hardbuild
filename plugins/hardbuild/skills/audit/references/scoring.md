# HardBuild scoring & confidence model

The point of a score is to be *trustworthy*, not flattering. Two numbers travel together: **Score** (how good the area is) and **Confidence** (how sure we are of the score). Never report one without the other.

## Check status → score value
| Status | Value | Meaning |
|--------|-------|---------|
| PASS | 1.0 | Requirement met, evidence attached |
| PARTIAL | 0.5 | Met in some places / partly; evidence shows both |
| FAIL | 0.0 | Not met, evidence shows the gap |
| N/A | excluded | Does not apply to this project (say why in one clause) |

**Area score** = Σ(weight × value) / Σ(weight of non-N/A checks) × 100, rounded to an integer.

## Check weight
| Weight | Use for |
|--------|---------|
| 3 | Would block launch or cause data loss, breach, outage, legal exposure, or lost revenue |
| 2 | Materially hurts users, conversion, maintainability, or cost |
| 1 | Polish, consistency, best practice |

## Evidence type → confidence
| Evidence type | Conf | What it means |
|---------------|------|---------------|
| VERIFIED | 100 | You ran a command, test, query, or browser check and read the result (quote it) |
| READ | 85 | You read the relevant code/config and cite file:line |
| INFERRED | 50 | Concluded from indirect signals (a dep is present, a pattern is typical) |
| UNCHECKED | 0 | Could not inspect (no access, no URL, out of time). Status must be FAIL or N/A, never PASS |

**Area confidence** = Σ(weight × conf) / Σ(weight of non-N/A checks), rounded.

A PASS with UNCHECKED evidence is forbidden. If you did not look, it did not pass.

## Grade bands and caps
A ≥90 · B 80–89 · C 70–79 · D <70.
- Any open **CRITICAL** finding caps the area grade at **D** and marks it *not ship-ready*, whatever the arithmetic says.
- Confidence < 90% → flag ⚠ and fill the "To raise confidence" section with the exact commands/access that would convert INFERRED/UNCHECKED into VERIFIED.

## Severity of findings
| Sev | Definition | Timing |
|-----|------------|--------|
| CRITICAL | Data loss/exposure, auth bypass, payment error, outage, legal violation, or the core job of the app does not work | Fix before any release |
| HIGH | Clear user harm or revenue/cost impact; broken on mobile; missing error handling on a main path | Fix this release |
| MEDIUM | Degrades quality or maintainability; inconsistent; missing in edge cases | Next release |
| LOW | Polish, nits, nice-to-have | Backlog |

## Finding rules (borrowed from the best audit repos, enforced here)
1. **Location or it didn't happen.** Every finding has `file:line`, or `URL + selector`, or `command → result`. No location → delete the row.
2. **One root cause, one finding.** Deduplicate across checks and across areas; reference the other area instead of repeating.
3. **Fix + verify.** Every CRITICAL/HIGH row names a concrete fix and the command/action that proves it.
4. **Claim vs code.** Anything the UI, docs, landing page, pricing, or legal pages *promise* must be traced to the code that delivers it. A promise with no implementation is a finding in the promising area (copy/legal/billing) *and* a note in the engineering area.
5. **Suppression is explicit.** `.audit-ignore` lines look like `path:line  tag  # reason`. The reason is mandatory. The audit reads this file and never writes it.
6. **Convergence.** For a full audit, after the last area, do one extra "fresh eyes" pass over the top findings. Stop when a pass adds zero new CRITICAL/HIGH.

## Overall score (scorecard)
Overall = mean of area scores, weighted: Security, Identity & Access, Database, Error Handling, Test Coverage, Billing & Tax, Privacy ×2; all others ×1. Overall confidence = same weighting over area confidences. Ship-ready = no open CRITICAL anywhere AND overall ≥80 AND overall confidence ≥85.
