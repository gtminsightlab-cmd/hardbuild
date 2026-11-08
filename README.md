# HardBuild — Hercules-style quality system for Claude Code

**The problem it solves:** Claude Code builds that are thin. Stubs left behind, features half-wired, "done" declared while typecheck is red. HardBuild makes "done" something that is *proven*, and gives you the same 24-area audit console you get in Hercules — with a score and a confidence number per area — inside any Claude Code project.

Tuned for **Next.js + Supabase + Vercel**, stack-detected so it adapts.

## What you get

| Piece | What it does | When it runs |
|-------|--------------|--------------|
| **Stop gate** (hook) | Blocks Claude from finishing while typecheck / lint / tests fail, while added lines contain TODO/stubs/placeholders/secrets, or while new files are not imported anywhere ("built but not wired in"). After 3 blocked attempts it yields but forces an honest "NOT done" report. | Automatically, every time Claude tries to stop after editing code |
| **Thin-build check** (hook) | Scans each file as Claude writes it. Hard smells (TODO, `not implemented`, lorem ipsum, stubs, pasted keys) are bounced back immediately so Claude finishes *that* file before moving on. | Automatically, on every Edit/Write |
| **Session rules** (hook) | Injects the Definition of Done and the current scorecard into every session. | Session start |
| `/hardbuild:audit <area \| group \| all>` | The 24-area audit. Each area: weighted checks → PASS/PARTIAL/FAIL with evidence → **Score 0–100 + Confidence %** → severity-ranked findings with `file:line` → fix plan. Writes `audits/<area>.md` and updates `audits/AUDIT-SCORECARD.md` as it goes (and mirrors to Google Drive when a Drive tool is connected). | On demand |
| `/hardbuild:ship-gate` | Executable Definition of Done: runs every gate, scans the change set, checks wiring (env vars, migrations, routes, auth/validation), then an independent **verifier** agent reproduces the "done" claim. Verdict: `DONE` or `NOT DONE`. | Before you say done / open a PR / deploy |
| `/hardbuild:harden <area \| all>` | Fix mode. Takes audit findings and fixes them in severity waves (CRITICAL → HIGH → MEDIUM), gating each wave on typecheck/lint/tests, reverting over-reach, then re-auditing until no CRITICAL/HIGH remain. | After an audit |
| `auditor` / `verifier` agents | Read-only subagents. `auditor` runs one area; `verifier` reproduces claims from scratch and cannot edit anything. | Used by the skills; also `@agent-hardbuild:verifier` directly |

### The 24 audit areas (same taxonomy as Hercules)
**Product & UX:** product · design · mobile · performance · documentation
**Engineering & Scale:** code-quality · accessibility · scalability · error-handling · database · testing · integrations · cloud-cost
**Security & Access:** security · identity-access · dependencies
**Marketing & Revenue:** seo · landing-page · copy-content · branding · i18n · billing-tax
**Legal & Compliance:** legal · privacy

### How scoring works (short version)
Each check has a weight (3 = would block launch, 2 = material, 1 = polish) and a status (PASS 1.0 · PARTIAL 0.5 · FAIL 0). **Score** = weighted pass %. Each check also records *how* it was verified: VERIFIED (ran a command — 100) · READ (cited file:line — 85) · INFERRED (50) · UNCHECKED (0, and it cannot PASS). **Confidence** = weighted mean of those. Any open CRITICAL caps the grade at D. Confidence under 90% must come with the exact commands/access that would raise it. Full model: `plugins/hardbuild/skills/audit/references/scoring.md`.

## Install

**From GitHub (recommended — one install, every project):**
```
/plugin marketplace add gtminsightlab-cmd/hardbuild
/plugin install hardbuild@hardbuild
```
Or from a shell: `claude plugin marketplace add gtminsightlab-cmd/hardbuild && claude plugin install hardbuild@hardbuild`

**From the zip (per project / offline):** unzip, then `claude --plugin-dir ./hardbuild/plugins/hardbuild` or add it via `/plugin marketplace add ./hardbuild`.

**Requirements:** `jq` and `git` on PATH (both standard on macOS/Linux; `brew install jq` if missing).

## Set up a project (2 minutes)
1. Copy `plugins/hardbuild/templates/.hardbuild.json` to your project root and fill in `audit.project`, `audit.productionUrl`, `audit.primaryCta`, `audit.billing`, etc. Leave `commands.*` empty to auto-detect from `package.json` scripts.
2. Paste `plugins/hardbuild/templates/RULES.md` into your project's `CLAUDE.md` (the SessionStart hook also injects it, but CLAUDE.md makes it permanent and visible to teammates).
3. Make sure `package.json` has `typecheck`, `lint`, and `test` scripts — the gate uses whatever exists and skips what doesn't.
4. Run `/hardbuild:audit all` once to create `audits/AUDIT-SCORECARD.md`. Commit the `audits/` folder so scores are tracked over time.

## Daily use
- Build normally. If Claude leaves a stub, the thin-build hook bounces it. If Claude tries to stop with a red build or an orphan file, the Stop gate blocks and lists exactly what to fix.
- Before you accept "done": `/hardbuild:ship-gate` (add `--build` before a deploy).
- Weekly or before a release: `/hardbuild:audit all` → read the scorecard → `/hardbuild:harden all`.
- Something feels off in one area: `/hardbuild:audit security database`.

## Tuning
`.hardbuild.json`:
- `gates.*` — turn individual gates on/off (`build` is off by default; `next build` is slow).
- `commands.*` — override auto-detected commands.
- `budgetSeconds` — per-gate time limit (default 240). `maxBlocks` — how many times the Stop gate blocks before yielding with a forced honest report (default 3).
- `ignorePaths` — folders the smell/orphan scans skip.
- Mark an intentional exception on a line with `// hardbuild-ok <reason>`.
- Suppress an audit finding with `.audit-ignore`: `path:line  TAG  # reason` (reason required; the audit only reads this file).

## Where the ideas came from
Stack detection and launch-blocker framing from [bzsasson/pre-launch-audit-skill](https://github.com/bzsasson/pre-launch-audit-skill) (MIT). Lens-per-pass convergence, "no finding without a location", `.audit-ignore`, and gated fix waves from [apoorvjain25/production-audit](https://github.com/apoorvjain25/production-audit) (MIT). Stop-hook build gates and read-only verifier agents from the Claude Code hooks docs, [hamelsmu/claude-review-loop](https://github.com/hamelsmu/claude-review-loop), and community write-ups. The score + confidence model, the 24-area check library, the orphan-file gate, and the thin-build hook are original to HardBuild.

## Layout
```
.claude-plugin/marketplace.json
plugins/hardbuild/
  .claude-plugin/plugin.json
  hooks/hooks.json                 SessionStart · PostToolUse(Edit|Write) · Stop · SubagentStop
  scripts/                         lib.sh · stop-gate.sh · thin-build-check.sh · session-context.sh · detect-stack.sh
  skills/audit/SKILL.md            /hardbuild:audit orchestrator
  skills/audit/checks/*.md         24 check files (weighted checks, verify commands, fail patterns)
  skills/audit/references/scoring.md
  skills/ship-gate/SKILL.md        /hardbuild:ship-gate
  skills/harden/SKILL.md           /hardbuild:harden
  agents/auditor.md · agents/verifier.md
  templates/                       .hardbuild.json · RULES.md · audit-report.md · AUDIT-SCORECARD.md
```

MIT © Ronnie O'Dell
