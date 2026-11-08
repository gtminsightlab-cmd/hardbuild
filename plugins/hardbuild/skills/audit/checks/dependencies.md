# Dependency & Supply Chain audit — checks

**Purpose:** Check for outdated, vulnerable, or risky dependencies — anything in `node_modules`, the lockfile, or CI that could ship a known exploit, an abandoned library, or code nobody reviewed.
**Scorecard row:** Dependency & Supply Chain · **Report:** `audits/dependencies.md` · **Overlaps:** Security (SEC-13 headline vuln count; secrets), Performance (bundle size of heavy deps), Build & CI (lockfile use in pipeline), Legal (license obligations). Reference, don't repeat.

## Inputs to gather first
- Package manager: presence of `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, or `bun.lockb`/`bun.lock`; `packageManager` field in `package.json`.
- `package.json` (`dependencies`, `devDependencies`, `engines`, `overrides`/`resolutions`), `.nvmrc`/`.node-version`, `.github/workflows/*.yml`, `.github/dependabot.yml` or `renovate.json`.
- Vercel project Node version (`mcp__Vercel__get_project` → `nodeVersion`) when the MCP is available.
- Network access for `pnpm audit`/`npm view`; if offline, mark affected checks INFERRED/UNCHECKED, never PASS.

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **DEP-01 · 3 · No high/critical vulnerabilities in production dependencies.**
  VERIFY: `pnpm audit --prod --audit-level=high` (`npm audit --omit=dev --audit-level=high` / `yarn npm audit --environment production --severity high` / `bun audit --prod`) → quote the summary counts. For each high/critical: is it reachable (direct dep or runtime transitive), and is a fixed version available (`pnpm audit --fix` dry-run, or `overrides`)? Else READ `pnpm-lock.yaml` for the known-bad versions named in recent advisories for `next`, `@supabase/*`, `undici`, `jsonwebtoken`, `axios`.
  FAIL PATTERN: `critical: 2` ignored for months because the fix needs a major bump; `audit` run only on devDependencies.
- **DEP-02 · 2 · Outdated majors are known and tracked.**
  VERIFY: `pnpm outdated --long` (`npm outdated`) → list packages ≥ 1 major behind; for framework-level ones (`next`, `react`, `@supabase/ssr`, `@supabase/supabase-js`, `tailwindcss`, `typescript`, `zod`) state the gap and whether a tracking issue exists. Two or more majors behind on a framework package → FAIL; one major with a tracked plan → PARTIAL.
  FAIL PATTERN: `next@13` on a project started in 2025; `zod@3` alongside `zod@4` imports split across the codebase.
- **DEP-03 · 3 · Lockfile is committed and used in CI and on Vercel.**
  VERIFY: `git ls-files | grep -E "^(pnpm-lock.yaml|package-lock.json|yarn.lock|bun.lockb|bun.lock)$"` → exactly one; `git check-ignore -v pnpm-lock.yaml` → not ignored. `grep -rn "frozen-lockfile\|npm ci\|--immutable" .github/workflows` → install step is deterministic. Vercel: `vercel.json`/project `installCommand` is empty (default uses frozen lockfile) or explicitly `pnpm install --frozen-lockfile`. `packageManager` field present so Corepack picks the same pnpm.
  FAIL PATTERN: two lockfiles (`package-lock.json` *and* `pnpm-lock.yaml`) both committed; CI runs `pnpm install` without `--frozen-lockfile` and resolves differently than local.
- **DEP-04 · 3 · Node, Next, and React versions are supported (not EOL).**
  VERIFY: `node -v` vs `.nvmrc`/`engines.node`; Node must be an Active or Maintenance LTS line (as of late 2026: 22.x or 24.x; 18.x and 20.x are EOL). `pnpm ls next react react-dom --depth 0` → Next on a currently supported major (latest or latest-1 receiving security patches), React matching what that Next requires. Vercel project `nodeVersion` must match.
  FAIL PATTERN: `engines.node: ">=16"`; Vercel pinned to Node 18 while local runs 22; React 19 with a Next 14 peer-dep warning silenced.
- **DEP-05 · 2 · No abandoned packages in production dependencies.**
  VERIFY: for each prod dependency not maintained by a large org, `npm view <pkg> time.modified` (batch: `for p in $(node -e "console.log(Object.keys(require('./package.json').dependencies).join(' '))"); do echo "$p $(npm view $p time.modified 2>/dev/null)"; done`) → flag last publish > 2 years ago; also check `npm view <pkg> deprecated`. Cite each hit with its replacement.
  FAIL PATTERN: `request`, `moment`, `node-sass`, `react-beautiful-dnd`, `@supabase/auth-helpers-nextjs` (deprecated in favor of `@supabase/ssr`).
- **DEP-06 · 1 · No duplicate-purpose packages.**
  VERIFY: `node -e "const d=require('./package.json');console.log(Object.keys({...d.dependencies,...d.devDependencies}).sort().join('\n'))"` and scan for pairs: date (`moment`/`dayjs`/`date-fns`/`luxon`), HTTP (`axios`/`node-fetch`/`got`/`ky` next to native `fetch`), state (`redux`+`zustand`+`jotai`), forms (`formik`+`react-hook-form`), icons (`react-icons`+`lucide-react`+`@heroicons/react`), validation (`yup`+`zod`), UUID (`uuid` next to `crypto.randomUUID`). `pnpm why <pkg>` to confirm they are direct, not transitive.
  FAIL PATTERN: three icon libraries each imported in one component.
- **DEP-07 · 2 · No heavy dependencies in client bundles.**
  VERIFY: `ANALYZE=true pnpm build` with `@next/bundle-analyzer` configured, or `npx next build` then inspect `.next/analyze/`; else `grep -rn "from 'moment'\|from 'lodash'$\|from \"lodash\"$\|from 'lodash/index'\|from 'rxjs'$\|from 'chart.js'$\|from 'pdfjs-dist'" app components --include=*.tsx` in `"use client"` files. Prefer `lodash-es` named imports or `lodash/<fn>`, `date-fns`, dynamic `import()` for charting/PDF/rich-text editors.
  FAIL PATTERN: `import _ from 'lodash'` and `import moment from 'moment'` (with all locales) in a client component on the landing page; a 400 kB PDF renderer loaded on every route via the root layout.
- **DEP-08 · 2 · License compatibility.**
  VERIFY: `npx license-checker --production --summary` (or `npx license-checker-rseidelsohn --production --onlyAllow "MIT;ISC;BSD-2-Clause;BSD-3-Clause;Apache-2.0;0BSD;CC0-1.0;Unlicense;BlueOak-1.0.0"`) → list anything GPL/AGPL/SSPL/"UNKNOWN"/"Custom". AGPL in a hosted SaaS and GPL linked into the server bundle are findings; LGPL and MPL need a note. Confirm the project's own `license` field is intentional (`UNLICENSED`/private for proprietary products).
  FAIL PATTERN: `UNKNOWN` licenses unreviewed; an AGPL PDF/diagram library bundled server-side in a commercial rater.
- **DEP-09 · 2 · Install scripts and postinstall hooks are reviewed.**
  VERIFY: `pnpm ls --depth Infinity --json | node -e "..."` is heavy; simpler: `grep -l '"postinstall"\|"preinstall"\|"install"' node_modules/*/package.json node_modules/@*/*/package.json 2>/dev/null` → list; each should be a known native builder (`sharp`, `esbuild`, `@swc/core`, `prisma`) or justified. pnpm ≥ 10 blocks scripts by default: check `pnpm.onlyBuiltDependencies` in `package.json` is a deliberate allow-list, and `.npmrc` does not set `ignore-scripts=false` globally.
  FAIL PATTERN: an obscure utility with a `postinstall` that runs `curl | sh`; `onlyBuiltDependencies` contains `"*"`.
- **DEP-10 · 2 · Automated dependency updates are configured.**
  VERIFY: `ls .github/dependabot.yml renovate.json .renovaterc* 2>/dev/null` → one exists, covers `npm` and `github-actions` ecosystems, with a schedule (weekly is fine) and grouping for minors/patches. Check recent merged PRs from the bot (`gh pr list --author app/dependabot --state merged --limit 5` or `--author app/renovate`) to prove it is not just configured but acted on.
  FAIL PATTERN: Dependabot enabled but 40 open PRs from six months ago; security-only updates with no version updates.
- **DEP-11 · 2 · GitHub Actions are pinned by commit SHA.**
  VERIFY: `grep -rnE "uses: [^ ]+@(v[0-9]+|main|master|latest)" .github/workflows` → each hit is a mutable tag; expected form is `uses: actions/checkout@<40-hex-sha> # v4.2.2`. Third-party (non-`actions/`, non-`github/`) actions on mutable tags are the priority. N/A if no workflows.
  FAIL PATTERN: `uses: some-vendor/deploy-action@main` with `secrets.VERCEL_TOKEN` in scope.
- **DEP-12 · 3 · No dependencies installed from git URLs, tarballs, or unknown registries.**
  VERIFY: `grep -nE '"(git\+|github:|https?://|file:|link:)' package.json`; `grep -nE "resolution: \{(tarball|commit)" pnpm-lock.yaml | head`; `cat .npmrc 2>/dev/null | grep -i registry` → only `registry.npmjs.org` or the org's vetted proxy. Any git/tarball dependency must be justified in a comment or ADR and pinned to a commit SHA.
  FAIL PATTERN: `"some-fork": "github:user/repo#main"` for a patched UI lib; a `.npmrc` pointing scoped packages at a registry nobody remembers.
- **DEP-13 · 2 · Typosquat and provenance sanity on unusual names.**
  VERIFY: for any dependency not recognized from the stack (`npm view <pkg> name version maintainers homepage repository.url dist.attestations` ) → confirm the repository URL resolves, weekly downloads are plausible (`https://api.npmjs.org/downloads/point/last-week/<pkg>`), and the name is not a one-character variant of a popular package (`reat`, `lodahs`, `@supabse/`, `nextjs-auth` vs `next-auth`). Prefer packages with npm provenance attestations.
  FAIL PATTERN: a package added by an AI-generated snippet that exists on npm with 12 downloads and no repository.
- **DEP-14 · 1 · SBOM can be produced (optional but cheap).**
  VERIFY: `npx @cyclonedx/cyclonedx-npm --output-file sbom.json --omit dev` or `pnpm sbom` where supported → file generates without error; optionally a CI step uploads it as an artifact. N/A for pre-launch prototypes; expected for anything with enterprise customers asking security questionnaires (carriers and PEO partners will).
  FAIL PATTERN: security questionnaire answered "we don't have a dependency inventory".

## Scoring notes
- DEP-01 (unfixed high/critical reachable at runtime), DEP-03 (no lockfile or non-deterministic install), DEP-04 (EOL Node/Next in production), DEP-12 (unvetted git/tarball source) failing → CRITICAL (grade cap D).
- DEP-11 is HIGH when a third-party action on a mutable tag has access to deploy secrets; MEDIUM otherwise.
- Without network access, DEP-01/02/05/13 cannot be VERIFIED: report them INFERRED from lockfile versions (conf 50) or UNCHECKED (FAIL), and list the exact commands under "To raise confidence".
- "To raise confidence": network for `pnpm audit`/`pnpm outdated`/`npm view`; `gh` auth for DEP-10 bot PR history; Vercel MCP `get_project` for the deployed Node version (DEP-04); a completed `ANALYZE=true pnpm build` for DEP-07.
