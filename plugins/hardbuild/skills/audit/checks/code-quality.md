# Code Quality audit — checks

**Purpose:** Review the quality and maintainability of the code. Find the places where the codebase is lying about being done (stubs, TODOs, placeholders shipped as features), where the type system has been switched off, and where the next change will be expensive or dangerous.
**Scorecard row:** Code Quality · **Report:** `audits/code-quality.md` · **Overlaps:** Test Coverage (test files, coverage %), Dependencies (outdated/unused packages), Database (schema quality — only the *generated types* question lives here), Error Handling (empty catches). Reference, don't repeat.

## Inputs to gather first
- Package manager and scripts: `cat package.json | jq '.scripts, .devDependencies | keys'` → note `typecheck`, `lint`, `format`, `prepare` (husky) scripts and whether `knip`/`ts-prune`/`prettier`/`eslint` are present.
- Source inventory: `git ls-files '*.ts' '*.tsx' | grep -vE "node_modules|\.next/|\.d\.ts$|__tests__|\.test\.|\.spec\." > /tmp/src.txt; wc -l < /tmp/src.txt`.
- Top-level layout: `ls app lib components hooks types supabase 2>/dev/null` (or `src/` equivalents).
- `.hardbuild.json → audit.features` (if present) to know which features are *claimed* shipped — needed for CQ-01.

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **CQ-01 · 3 · No thin-build smells in shipped source (TODO/FIXME/stub/placeholder/mock data behind a real UI).**
  VERIFY: `git grep -nIiE "\b(TODO|FIXME|HACK|XXX|STUB|stubbed|placeholder|not implemented|coming soon|mock(ed)?Data|dummy|lorem ipsum|hardcoded)\b" -- ':!*.md' ':!*.test.*' ':!*.spec.*' ':!*.stories.*' ':!node_modules'` → list every hit with `file:line`; then `git grep -nE "throw new Error\(['\"](Not implemented|TODO|unimplemented)" ` and `git grep -nE "return (null|\[\]|\{\});?\s*//" `. For each feature in `audit.features` (or each nav item / pricing bullet), open the handler that supposedly delivers it and confirm it talks to Supabase or a real service, not a constant.
  FAIL PATTERN: `// TODO: wire to Supabase` above `const data = MOCK_ROWS;` in a page that is linked from production nav; a button whose `onClick` is `() => toast('Coming soon')`; a server action that returns `{ ok: true }` without doing anything. Any hit on a user-reachable path = CRITICAL (claim vs code, scoring rule 4).
- **CQ-02 · 3 · TypeScript strict mode with `noUncheckedIndexedAccess`.**
  VERIFY: `jq '.compilerOptions | {strict, noUncheckedIndexedAccess, noImplicitAny, strictNullChecks, skipLibCheck}' tsconfig.json` → `strict: true` and `noUncheckedIndexedAccess: true`; check no `extends` chain silently turns them off (`jq .extends tsconfig.json` and read the parent). `allowJs: true` with untyped `.js` in `lib/` is a PARTIAL.
  FAIL PATTERN: `"strict": false`, or `strict: true` but `"strictNullChecks": false` overriding it.
- **CQ-03 · 3 · Typecheck passes on the whole project.**
  VERIFY: `pnpm typecheck 2>&1 | tail -20` if the script exists, else `npx tsc --noEmit -p tsconfig.json 2>&1 | tail -20` → `0 errors`. Count errors: `npx tsc --noEmit 2>&1 | grep -c "error TS"`. If `next build` is the only gate, check `next.config.*` for `typescript.ignoreBuildErrors: true` — that is an automatic FAIL regardless of tsc output.
  FAIL PATTERN: `ignoreBuildErrors: true` so Vercel deploys with hundreds of type errors nobody sees.
- **CQ-04 · 2 · Lint passes and the config is real.**
  VERIFY: `pnpm lint 2>&1 | tail -20` or `npx eslint . --max-warnings=0 2>&1 | tail -20`. Then READ `eslint.config.*`/`.eslintrc*`: must extend `next/core-web-vitals` and `next/typescript` (or `@typescript-eslint/recommended`); count `"off"` rules: `grep -cE "['\"]off['\"]|: 0[,}]" eslint.config.* .eslintrc* 2>/dev/null`. More than ~5 disabled rules, or `no-explicit-any`, `no-unused-vars`, `react-hooks/exhaustive-deps` turned off = PARTIAL at best. `eslint.ignoreDuringBuilds: true` in `next.config.*` = FAIL.
  FAIL PATTERN: a config whose `rules` block is a wall of `off` to make CI green.
- **CQ-05 · 2 · `any` is not used at data boundaries.**
  VERIFY: `git grep -nE ":\s*any\b|as any\b|<any>|any\[\]" -- '*.ts' '*.tsx' ':!*.d.ts' ':!*.test.*' | wc -l` for the count; then `git grep -nE ":\s*any\b|as any\b" -- 'app/**/route.ts' 'app/**/actions.ts' 'lib/supabase/**' 'lib/api/**' 'supabase/functions/**'` → boundary hits are the ones that matter (request bodies, Supabase rows, webhook payloads, `searchParams`). Cite each boundary hit. Thresholds: 0 boundary hits PASS; boundary hits with a zod parse immediately after PARTIAL; raw `any` flowing into `.insert()`/`.update()` FAIL.
  FAIL PATTERN: `const body: any = await req.json()` or `(row as any).field` to dodge a missing generated type.
- **CQ-06 · 2 · Suppression comments are rare and justified.**
  VERIFY: `git grep -nE "@ts-ignore|@ts-expect-error|@ts-nocheck|eslint-disable" -- '*.ts' '*.tsx' | grep -vE "\.(test|spec|stories)\." ` → each `@ts-ignore` (prefer `@ts-expect-error`) and every `eslint-disable` without a trailing `-- reason` is a finding; `@ts-nocheck` on any non-generated file is a FAIL. Per-100-files ratio: ≤2 PASS, ≤10 PARTIAL, more FAIL.
  FAIL PATTERN: `// eslint-disable-next-line react-hooks/exhaustive-deps` on a `useEffect` that closes over a stale Supabase client.
- **CQ-07 · 2 · No dead code or unused exports.**
  VERIFY: `npx knip --reporter compact 2>&1 | tail -40` (preferred; reports unused files, exports, deps) or `npx ts-prune -e 2>&1 | grep -v "used in module" | head -40`. If neither runs (no network), READ: `git grep -lE "^export" components/ lib/ | while read f; do n=$(basename "$f" | sed 's/\.[jt]sx\?$//'); c=$(git grep -l "$n" -- '*.ts' '*.tsx' | grep -v "$f" | wc -l); [ "$c" = 0 ] && echo "$f"; done` to spot orphan modules. Also `ls app/**/page.tsx` and compare to nav/links — unreachable pages are dead code.
  FAIL PATTERN: `components/old/`, `lib/utils-v2.ts`, duplicated `page-backup.tsx` files still compiled into the bundle.
- **CQ-08 · 2 · File and function size outliers.**
  VERIFY: files — `git ls-files '*.ts' '*.tsx' | xargs wc -l | sort -rn | awk '$1>400 && $2!="total"' | head -20` (exclude `types/supabase.ts`, generated files, `*.d.ts`). Functions/components — `npx eslint . --no-eslintrc --parser @typescript-eslint/parser --rule '{"max-lines-per-function":["warn",{"max":80,"skipBlankLines":true,"skipComments":true}]}' 2>&1 | grep -c "max-lines-per-function"`, or READ the top 5 largest files and note any component/handler over ~80 lines doing fetch + transform + render. Thresholds: ≤3 outliers PASS; ≤10 PARTIAL; `page.tsx` files over 600 lines FAIL.
  FAIL PATTERN: a 1,200-line `app/dashboard/page.tsx` that holds every modal, query and form in one component.
- **CQ-09 · 1 · No near-duplicate components or utilities.**
  VERIFY: `npx jscpd --min-tokens 60 --reporters consoleFull --ignore "**/types/supabase.ts,**/*.test.*" app lib components 2>&1 | tail -30` if available; else `git ls-files '*.tsx' | xargs -n1 basename | sort | uniq -d` for same-named files and `git grep -lE "export (default )?function (format(Date|Currency|Money)|cn\b|classNames|sleep|debounce)" ` to spot re-implemented helpers. Cite pairs of files.
  FAIL PATTERN: `formatCurrency` in three places with three different rounding rules; `UserCard.tsx` and `MemberCard.tsx` differing by one prop.
- **CQ-10 · 1 · Consistent module boundaries (`app/` routes, `components/` UI, `lib/` logic, `supabase/` schema).**
  VERIFY: `git grep -nE "from ['\"](\.\./)+app/" -- 'components/**' 'lib/**'` → nothing in `lib/` or `components/` should import from `app/`; `git grep -lE "supabase\.from\(" -- 'components/**/*.tsx' | xargs grep -L "use client"` → data access inside presentational components is a boundary leak; `git grep -nE "^import .* from ['\"]\.\./\.\./\.\./" | wc -l` for deep relative imports when a `@/` alias exists (`jq .compilerOptions.paths tsconfig.json`).
  FAIL PATTERN: `components/ui/button.tsx` importing a server action; `lib/` reaching into `app/(dashboard)/...` for a type.
- **CQ-11 · 1 · Naming consistency.**
  VERIFY: `git ls-files 'components/**' 'lib/**' | xargs -n1 basename | sed 's/\..*//' | grep -cE "[A-Z]"` vs `grep -cE "^[a-z-]+$"` to see whether files are kebab-case or PascalCase — a mix is a finding; Supabase columns are `snake_case` while TS is `camelCase` — check a mapping layer exists (`git grep -nE "snakeToCamel|camelcase-keys|toCamel"`) or that the generated types are used directly and consistently (no `userId` and `user_id` both live in the same model). Boolean names start with `is/has/can`; hooks start with `use`.
  FAIL PATTERN: `getUser`, `fetchUser`, `loadUserData`, `useUser` all existing and doing different things.
- **CQ-12 · 1 · Formatting is enforced automatically.**
  VERIFY: `ls .prettierrc* prettier.config.* 2>/dev/null`; `jq '.scripts.prepare, .["lint-staged"]' package.json`; `ls .husky/pre-commit 2>/dev/null && cat .husky/pre-commit`; or a CI step (`grep -nE "prettier|lint" .github/workflows/*.yml`). Then actually run `npx prettier --check . 2>&1 | tail -5` → `All matched files use Prettier code style!`. Config present but `--check` failing = PARTIAL.
  FAIL PATTERN: prettier in devDependencies, never wired to a hook or CI, and 40% of files unformatted.
- **CQ-13 · 2 · Generated Supabase types are used, current, and the single source of truth.**
  VERIFY: `ls types/supabase.ts lib/database.types.ts supabase/types.ts 2>/dev/null` and `head -5` to confirm it is the `supabase gen types` output (`export type Json =` / `export type Database =`). Confirm the client is typed: `git grep -nE "createClient<Database>|createServerClient<Database>|createBrowserClient<Database>"`. Freshness: `npx supabase gen types typescript --local > /tmp/gen.ts && diff -q /tmp/gen.ts types/supabase.ts` (or `--project-id` / Supabase MCP `generate_typescript_types`) → no diff. Hand-written row interfaces are a finding: `git grep -nE "^(export )?(interface|type) \w+(Row|Table|Record) " -- 'types/**' 'lib/**' | grep -v supabase.ts`.
  FAIL PATTERN: `interface Profile { id: string; email: string }` in `types/user.ts` drifting from the real `profiles` table that gained `org_id` two migrations ago.
- **CQ-14 · 1 · No commented-out code blocks.**
  VERIFY: `git grep -nE "^\s*//\s*(const|let|var|if|return|await|import|export|function|<[A-Z])" -- '*.ts' '*.tsx' | wc -l` and `git grep -cE "^\s*\{/\*" -- '*.tsx' | awk -F: '$2>3'` for JSX blocks commented out; ≤5 lines total PASS, ≤25 PARTIAL, more FAIL. Cite the three largest blocks.
  FAIL PATTERN: 80 lines of the previous implementation left under `// old version` in a shipped server action.

## Scoring notes
- CQ-01 failing on any user-reachable path (a placeholder, stub or mock standing in for a claimed feature) → CRITICAL finding (grade cap D) and a cross-reference note in the feature's owning area (Billing, Copy, etc.). This is the single most important check in this area: a thin build with perfect lint is still a thin build.
- CQ-03 FAIL via `ignoreBuildErrors: true`, or CQ-02 FAIL (`strict: false`) on a project that touches money or PII → HIGH; cap at C.
- Counts matter: report the number for CQ-05/06/08/14 alongside the status so the next audit can show movement.
- Commands in CQ-03/04/07/12/13 produce VERIFIED (100). Reading `tsconfig.json`/`eslint.config.*` without running the tool is READ (85). Guessing from `devDependencies` alone is INFERRED (50) — say so.
- "To raise confidence": `pnpm install` so `tsc`, `eslint`, `prettier --check` and `knip` can run; Supabase CLI or MCP access to regenerate types for CQ-13; the `audit.features` list in `.hardbuild.json` so CQ-01 can be traced feature by feature.
