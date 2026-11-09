# Test Coverage & QA audit — checks

**Purpose:** Find untested critical paths and missing tests — the places where a regression would ship silently because nothing would go red.
**Scorecard row:** Test Coverage & QA · **Report:** `audits/testing.md` · **Overlaps:** Database (RLS semantics — here only whether they are *tested*), Security (what to protect — here only whether it is *asserted*), CI/CD & Release (pipeline health beyond tests), Error Handling (behaviour under failure — here whether failure paths have tests). Reference, don't repeat.

## Inputs to gather first
- Surface inventory (shared with Security): route handlers (`route.ts`), server actions (`"use server"`), middleware, Supabase policies, edge functions, pricing/rating/validation modules.
- Test tooling: `cat package.json | jq '.scripts, .devDependencies | with_entries(select(.key|test("vitest|jest|playwright|cypress|testing-library|msw|pgtap|supabase")))'`; config files `vitest.config.*`, `jest.config.*`, `playwright.config.*`, `supabase/tests/`.
- Test file list: `git ls-files | grep -E "\.(test|spec)\.(ts|tsx|js)$|__tests__/|supabase/tests/.*\.sql$|e2e/" ` → count and paths.
- CI: `ls .github/workflows` and which jobs run `test`/`playwright`/`supabase test`.
- Critical-path list for THIS app (write it down before checking): sign-up, sign-in/reset, the main object's create/update/delete, any payment or billing action, any export/email/send action, any role/permission change, every RLS policy on tenant tables.

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **TST-01 · 2 · A test runner exists and the suite runs green.**
  VERIFY: `pnpm test -- --run` (vitest) or `pnpm jest --ci` → quote the summary line (`Tests  N passed`). Zero tests or no `test` script = FAIL. A suite that fails locally = FAIL even if CI is green (CI may be skipping it).
  FAIL PATTERN: `"test": "echo \"no tests yet\" && exit 0"`.
- **TST-02 · 1 · Coverage is measured and thresholds enforced.**
  VERIFY: `pnpm test -- --run --coverage` → provider installed (`@vitest/coverage-v8`), summary table printed; READ `vitest.config.*` for `coverage.thresholds` (`lines/branches/functions/statements`, or `autoUpdate`/per-file). Thresholds absent = PARTIAL if coverage runs, FAIL if coverage is not configured. Do not grade on the percentage itself — grade on whether a drop would fail the build.
  FAIL PATTERN: coverage runs in CI, uploads a badge, enforces nothing.
- **TST-03 · 3 · Every critical path has at least one test that exercises it (the key check).**
  VERIFY: build a two-column table: critical path (from Inputs) → test file(s) that import or hit it. Method: for each route/action file, `git grep -ln "<exported fn name>\|<route path>" -- '*.test.*' '*.spec.*' e2e/` ; for each RLS tenant table, `grep -rln "<table>" supabase/tests e2e __tests__`. Any critical path with no test = one HIGH finding each (CRITICAL for auth, payment, tenant isolation). Attach the table to the report — the list of uncovered paths is the deliverable of this area.
  FAIL PATTERN: 140 tests, all on `utils/format*.ts`; zero tests touch `app/(app)/quotes/actions.ts` or `stripe/webhook/route.ts`.
- **TST-04 · 2 · Pure business logic has unit tests.**
  VERIFY: locate pricing/rating/commission/eligibility/date math and every zod schema (`grep -rlnE "z\.object\(" --include=*.ts | grep -v test`); for each module confirm a sibling test with boundary cases (zero, negative, max, rounding, timezone, empty string, unicode). Schemas: tests should assert both a valid parse and the specific rejection messages the UI shows.
  FAIL PATTERN: `calculatePremium()` with 9 branches and one test asserting the happy-path number.
- **TST-05 · 2 · Server actions and route handlers have integration tests.**
  VERIFY: tests that call the handler/action directly with a Request/FormData and a Supabase client pointed at local Supabase (`supabase start`, `SUPABASE_URL=http://127.0.0.1:54321`) or a typed mock (`vi.mock('@/lib/supabase/server')`); each must assert the 401/403 path, the validation-error path, and the success path. `grep -rn "auth.getUser\|redirect(" <action file>` vs assertions in its test. Mocks that always return a user and never test the unauthenticated branch = PARTIAL.
  FAIL PATTERN: `vi.mock` returns `{ data: { user: { id: 'test' } } }` globally; the auth guard is never exercised.
- **TST-06 · 2 · E2E covers the top 3 user journeys.**
  VERIFY: `ls e2e tests/e2e playwright/` and `playwright.config.*` (`webServer`, `baseURL`, `projects` incl. a mobile viewport); the three journeys (typically: sign-up → first object created; the money path; the main daily task) must each appear as a `test(` with assertions on visible outcome, not just navigation. `pnpm exec playwright test --list` → quote the test titles. No Playwright/Cypress = FAIL.
  FAIL PATTERN: one E2E test: "homepage loads".
- **TST-07 · 3 · RLS policies are tested as a non-owner.**
  VERIFY: `supabase test db` with pgTAP files in `supabase/tests/*.sql` using `tests.authenticate_as()`/`set local role authenticated; set local request.jwt.claims` and asserting `results_eq`/`is_empty` for another tenant's rows; or JS tests that create two users via `supabase.auth.admin.createUser` and assert user B gets 0 rows / `42501` on user A's data. Every tenant table in Database DB-12 needs at least a read-denied and a write-denied assertion. Tests that only use the service-role key prove nothing here.
  FAIL PATTERN: RLS "tested" by logging in with one account and seeing data appear.
- **TST-08 · 1 · No disabled or focused tests left behind.**
  VERIFY: `grep -rnE "\.(skip|only|todo)\(|xit\(|xdescribe\(|xtest\(|fit\(|fdescribe\(" --include=*.test.* --include=*.spec.* .` → `.only` anywhere = FAIL (CI silently runs one test); `.skip`/`xit` without a `// TODO(#issue)` comment = PARTIAL; `test.fixme` in Playwright counts as skip.
  FAIL PATTERN: `describe.only('new pricing', ...)` committed 3 weeks ago; suite "green" since.
- **TST-09 · 2 · Tests assert behaviour, not just snapshots or render.**
  VERIFY: `grep -rnc "toMatchSnapshot\|toMatchInlineSnapshot" --include=*.test.*` vs total `expect(` count; `git ls-files | grep __snapshots__ | wc -l`. Read 5 random component tests: each should assert user-visible text/role/state or a called mutation, not `expect(container).toBeTruthy()`. Snapshot-only files or "renders without crashing" tests = PARTIAL (counted toward TST-03 as *not covering* the path).
  FAIL PATTERN: 40 snapshot files updated wholesale with `-u` in a single "fix tests" commit.
- **TST-10 · 1 · Flakiness is contained, not hidden.**
  VERIFY: `grep -rnE "retries:|test\.retry|retry\(|jest-retry|vitest.*retry" vitest.config.* playwright.config.* .github/workflows/*` → global `retries: 3` on unit tests = masking; Playwright `retries: 1-2` in CI only is acceptable. `grep -rnE "setTimeout\(|waitForTimeout\(|sleep\(" --include=*.test.* --include=*.spec.* e2e/` → hard sleeps are flake sources; count them. Check CI history if accessible (`gh run list --workflow test -L 20 --json conclusion`) for re-run patterns.
  FAIL PATTERN: `waitForTimeout(3000)` sprinkled through E2E; CI job "Re-run failed" is the normal path.
- **TST-11 · 1 · Test data comes from factories, not copy-pasted fixtures.**
  VERIFY: look for `tests/factories/*`, `@faker-js/faker`, `fishery`, or builder functions (`makeQuote({ status: 'bound' })`); `grep -rnE "id: ['\"][0-9a-f-]{36}['\"]" --include=*.test.* | wc -l` → many hard-coded UUIDs/emails = fixtures that break on schema change. Supabase integration tests must create and clean their own rows (`afterEach` delete, or per-test schema/transaction), not depend on `seed.sql` row ids.
  FAIL PATTERN: every test imports `fixtures/quote.json` with 48 fields; adding a NOT NULL column breaks 60 tests.
- **TST-12 · 1 · Generated DB types are checked, not trusted.**
  VERIFY: a type-level test or CI step — `tsc --noEmit` runs in CI (`grep -rn "tsc\|typecheck" .github/workflows package.json`), plus either `expectTypeOf`/`tsd` tests on key `Database['public']['Tables'][...]['Row']` shapes or a CI step that regenerates types and fails on diff (`supabase gen types ... | diff - types/supabase.ts`). Missing typecheck in CI = FAIL; typecheck without the regen-diff = PARTIAL (pair with Database DB-10).
  FAIL PATTERN: `"build": "next build"` with `typescript.ignoreBuildErrors: true` in `next.config`.
- **TST-13 · 2 · CI runs the tests on every PR and blocks merge.**
  VERIFY: READ `.github/workflows/*.yml` → `on: pull_request` job that runs lint, typecheck, unit tests, and (ideally) Playwright against a preview URL or `next start`; `gh api repos/{owner}/{repo}/branches/main/protection` (or `rulesets`) → required status checks include that job. Vercel-only "build passes" is not a test gate. No workflow = FAIL; workflow but not a required check = PARTIAL.
  FAIL PATTERN: tests run on `push` to `main` only — after the merge.
- **TST-14 · 1 · Visual and mobile checks exist (optional but scored when claimed).**
  VERIFY: Playwright `projects` with `devices['iPhone 14']` or similar; screenshot assertions (`toHaveScreenshot`) or Chromatic/Percy/Storybook test-runner in CI; `@axe-core/playwright` for a11y smoke. N/A for internal tools with no mobile claim; FAIL if the landing page or README promises "mobile-ready" and nothing checks it (scoring rule 4, claim vs code).
  FAIL PATTERN: "fully responsive" on the pricing page; Playwright runs desktop Chromium only.

## Scoring notes
- TST-03 failing on auth, payment, or tenant-isolation paths → CRITICAL; TST-07 failing on any tenant table → CRITICAL (grade cap D). TST-01 FAIL with any customer data in production → CRITICAL.
- TST-03 is scored PARTIAL only when ≥ half the critical paths are covered; otherwise FAIL — this check is the headline number of the report.
- A red `.only` (TST-08) also downgrades TST-01 to PARTIAL regardless of the green summary line.
- Grades here are about *risk left untested*, not coverage %; a 40% suite that covers every critical path beats an 85% suite of util tests.
- "To raise confidence": run `pnpm test -- --run --coverage`, `pnpm exec playwright test --list`, `supabase start && supabase test db`, `gh run list` for CI history, branch-protection read access. Without a runnable suite, TST-01/02/06/07 are READ at best (conf 85) and TST-10 is INFERRED (50).
