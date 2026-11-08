# {{AREA}} Audit — {{PROJECT}}

**Date:** {{YYYY-MM-DD}} · **Score:** {{SCORE}}/100 ({{GRADE}}) · **Confidence:** {{CONFIDENCE}}% · **Ship-ready for this area:** {{YES/NO}}
**Scope:** {{what was inspected: paths, URLs, commands}} · **Stack:** {{from detect-stack}}

## Verdict (3 sentences max)
{{What the state of this area is, the single biggest risk, and what to do first.}}

## Findings
Ordered by severity. Every row has evidence or it was dropped.

| # | Sev | Finding | Evidence (file:line / URL+selector / command → result) | Fix | Verify with |
|---|-----|---------|------------------------------------------------------------|-----|-------------|
| 1 | CRITICAL | | | | |
| 2 | HIGH | | | | |
| 3 | MEDIUM | | | | |
| 4 | LOW | | | | |

## Checklist results
| Check | Weight | Status | Evidence type | Evidence |
|-------|--------|--------|---------------|----------|
| | 3 | PASS / PARTIAL / FAIL / N/A | VERIFIED / READ / INFERRED / UNCHECKED | |

**Score math:** Σ(weight × status) / Σ(weight of non-N/A checks) × 100 = {{SCORE}}
**Confidence math:** Σ(weight × evidence confidence) / Σ(weight of non-N/A checks) = {{CONFIDENCE}}%

## To raise confidence to ≥90%
{{Commands or access that would turn INFERRED/UNCHECKED into VERIFIED — e.g. "run `pnpm exec playwright test` against staging", "grant Supabase advisor access".}}

## What's good (keep doing this)
{{2–5 specifics with file refs — so fixes don't regress strengths.}}

## Fix plan
| Order | Finding # | Effort (S/M/L) | Owner | Gate to pass |
|-------|-----------|----------------|-------|--------------|

## Suppressed (from .audit-ignore)
{{path:line · tag · reason — or "none"}}
