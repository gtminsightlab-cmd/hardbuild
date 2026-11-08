---
name: audit
description: Hercules-style product audit for this codebase. Runs one of 24 areas, a group, or all — with a 0–100 score, a confidence %, severity-ranked findings with file:line evidence, and a fix plan. Writes audits/<area>.md and updates audits/AUDIT-SCORECARD.md. Use when asked to audit, QA, review quality, check readiness, or "how solid is X".
argument-hint: "[all | product | engineering | security | marketing | legal | <area> ...]  e.g. /hardbuild:audit security database"
allowed-tools: Read Grep Glob Bash Write Edit Agent WebFetch
---

# /hardbuild:audit — run a scored, evidence-based audit

You are running a structured audit modeled on a product-grade audit console. The output is a **score with a confidence**, not vibes. Read `references/scoring.md` first and follow it exactly.

## Arguments
`$ARGUMENTS` = space-separated list of areas, groups, or `all`. Empty → ask which (offer: all · product · engineering · security · marketing · legal · a single area).

Groups → areas (check files live in `checks/<slug>.md`):
- **product**: product, design, mobile, performance, documentation
- **engineering**: code-quality, accessibility, scalability, error-handling, database, testing, integrations, cloud-cost
- **security**: security, identity-access, dependencies
- **marketing**: seo, landing-page, copy-content, branding, i18n, billing-tax
- **legal**: legal, privacy
- **all**: everything, in the order above

Aliases: a11y→accessibility · auth→identity-access · perf→performance · db→database · tests/qa→testing · deps/supply-chain→dependencies · docs→documentation · lpo→landing-page · copy→copy-content · brand→branding · i18n/l10n→i18n · billing/tax/stripe→billing-tax · cloud/cost/hosting→cloud-cost · mobile/tablet/responsive→mobile · errors→error-handling · scale/reliability→scalability · privacy/gdpr→privacy

## Phase 0 — Inventory (always, once per run)
1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh"` and read `.hardbuild.json` (`audit.*` keys: project name, productionUrl, stagingUrl, primaryCta, targetMarkets, mirrorToDrive). If the stack JSON is surprising (e.g. not Next.js), say so and adapt the checks — do not run Next.js checks against a Python app.
2. Build a short **surface inventory**: routes/pages (`page.tsx`), API routes (`route.ts`), server actions (`"use server"`), Supabase tables/migrations/edge functions, env vars referenced (`process.env.X`), third-party SDKs, background jobs/crons (`vercel.json` crons), emails sent, public marketing pages, legal pages. Keep it to one screen. Every area audit reads this inventory so nothing is missed.
3. Read `.audit-ignore` if present. Honor it; list suppressions in each report.
4. Create `audits/` if missing. If `audits/AUDIT-SCORECARD.md` is missing, copy `${CLAUDE_PLUGIN_ROOT}/templates/AUDIT-SCORECARD.md` and fill the project name.

## Phase 1 — Run each area
For each area, in order:
1. Read `checks/<slug>.md`. It lists weighted checks, the Next.js/Supabase/Vercel-specific way to verify each, and the usual failure patterns.
2. **Prefer VERIFIED evidence.** Run the commands the check file gives (typecheck, lint, tests, `npm audit`, grep patterns, SQL via Supabase MCP if available, `curl -sI` against productionUrl, Lighthouse/Playwright if installed). Only fall back to READ (cite file:line) and then INFERRED. Never mark PASS without looking.
3. Record every check as PASS/PARTIAL/FAIL/N/A with weight, evidence type, and evidence. Turn every FAIL/PARTIAL into a finding row with severity, fix, and verify-command. Dedupe against findings already written by earlier areas (reference them).
4. Compute score and confidence per `references/scoring.md`. Apply the CRITICAL cap.
5. Write `audits/<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/audit-report.md`. Fill every section; "To raise confidence" is mandatory when confidence < 90.
6. Update the area's row in `audits/AUDIT-SCORECARD.md` immediately (score, grade, conf, crit, high, date). **Save as you go** — a long run must leave partial results on disk if the session dies.
7. If `audit.mirrorToDrive` is true and a Google Drive tool is available in this session (e.g. `mcp__Google_Drive__create_file`), upload the finished report to a folder named `<driveFolder>/<project>/<YYYY-MM-DD>` right after writing it (create the folder on the first upload). If no Drive tool is available, skip silently and mention it once in the final summary.

**Parallelism:** for `all` or a group, you may run areas as parallel subagents using the `hardbuild:auditor` agent — one area per subagent, each told the inventory, the check file path, the scoring rules, and the report path. Collect their reports; you (the orchestrator) own dedupe, the scorecard, and the overall verdict. Keep ≤5 in flight so results stay reviewable.

## Phase 2 — Converge and verify (for `all` or any group)
1. One "fresh eyes" pass over all CRITICAL/HIGH findings: confirm each still has a valid location, is not a duplicate, and has a real fix. Drop anything that fails the location rule.
2. Spawn `hardbuild:verifier` (read-only) with the list of CRITICAL findings; it must independently reproduce each (open the file, run the command). Downgrade or remove anything it cannot reproduce; note the disagreement.
3. Compute Overall score, confidence, ship-ready per scoring.md. Fill the scorecard's **Top 10 fixes** (cross-area, by severity then effort) and **Run log**.

## Phase 3 — Report back
In chat, give: overall score + confidence + ship-ready verdict; per-area one-liners (score/conf/criticals); the top 5 fixes; and what would raise confidence. Link the files. Use large clear structure, no walls of text. Then offer `/hardbuild:harden` to fix in severity waves.

## Hard rules
- No finding without a location. No PASS without evidence. No score without confidence.
- Do not fix anything during an audit — audits are read-only except for writing `audits/`. Fixing happens in `/hardbuild:harden`.
- If an area is impossible to assess (no production URL for SEO, no Stripe for billing), mark checks N/A with the reason and say what input would unlock it; do not guess.
- Honor `.audit-ignore`; never edit it.
