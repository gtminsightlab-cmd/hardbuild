---
name: harden
description: Fix mode for audit findings. Takes audits/*.md (or one area), fixes findings in severity waves (CRITICAL → HIGH → MEDIUM), gating each wave on typecheck/lint/tests, reverting any over-reach, then re-audits the area until no CRITICAL/HIGH remain. Use after /hardbuild:audit, or when asked to "fix the audit findings" or "harden X".
argument-hint: "[area | all] [--max-wave MEDIUM|HIGH|CRITICAL]"
allowed-tools: Read Grep Glob Bash Write Edit Agent
---

# /hardbuild:harden — fix findings in gated waves

Audits find; this skill fixes — carefully, in waves, with proof, and without drifting into unrelated changes.

## 0. Load
- Read `audits/AUDIT-SCORECARD.md` and the report(s) for `$ARGUMENTS` (default: every area with open CRITICAL or HIGH). Build one deduplicated worklist: `id · area · sev · location · defect · fix · verify-command · effort`.
- Confirm the tree is clean or the user accepts working on top of uncommitted changes. Note the starting commit (`git rev-parse --short HEAD`) so the whole hardening can be reverted.
- Read `.hardbuild.json` for gate commands.

## 1. Waves
Default stop at MEDIUM (`--max-wave` changes it). For each wave, CRITICAL first:
1. **Plan the wave**: list the findings in it. Group by root cause. For each, state the minimal change.
2. **Fix** each finding at its location. Rules: smallest change that truly resolves the defect; no unrelated refactors; no new TODOs; update every caller when you change a signature; add or update the test that proves the fix when the finding was about behavior; update `.env.example`/docs when the fix adds config.
3. **Gate the wave**: run typecheck, lint, and tests (same detection as the Stop gate). Fix until green. If a gate cannot be made green without weakening it, stop and report — do not weaken it.
4. **Over-reach review**: `git diff --stat` and `git diff` since the wave started. Every hunk must map to a finding id. Revert hunks that don't (`git checkout -p` / targeted edits). State what you reverted.
5. **Verify each finding** with its verify-command; mark `FIXED` with the command output, or `OPEN` with why.
6. **Commit the wave** if the user wants commits (ask once at the start): `fix(<area>): <wave> findings <ids>` — with the project's commit conventions.

## 2. Re-audit
After the last wave, re-run `/hardbuild:audit <areas>` for the touched areas (or spawn `hardbuild:auditor` per area). If any CRITICAL/HIGH remains or was introduced, run one more wave on those only. Stop after two consecutive re-audits with zero CRITICAL/HIGH, or when you are only shuffling MEDIUMs.

## 3. Report
```
HARDEN: <areas>  waves: <n>  start <sha> → end <sha>
Fixed: <n> (CRIT a · HIGH b · MED c)   Open: <n> with reasons
Score: <area> before → after (conf before → after)
Reverted over-reach: <list or none>
Gates at end: typecheck ✔ lint ✔ tests ✔ (<x> passing)
Follow-ups the user must do: <env on Vercel, run migration, rotate key, …>
```
Update the scorecard rows and run log. Mirror reports to Google Drive if the audit config says so and a Drive tool is available.

## Rules
- A finding is FIXED only when its verify-command passes in your hands. Otherwise it is OPEN.
- Never trade one finding for another (e.g. fix an N+1 by removing the feature).
- Never touch billing, auth, or RLS without re-reading the Identity & Access and Database check files first; those fixes get a test.
- Keep the user informed between waves: one short status line per wave.
