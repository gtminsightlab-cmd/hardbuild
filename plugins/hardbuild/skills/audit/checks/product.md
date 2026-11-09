# Product audit — checks

**Purpose:** Check that your app truly solves the user's problem — the core job is reachable, finishable, and every promise the UI makes is backed by working code.
**Scorecard row:** Product · **Report:** `audits/product.md` · **Overlaps:** Copy & Content (microcopy wording), Accessibility (focus/keyboard on CTAs), Error Handling (what happens when an action fails), Analytics (event taxonomy detail), Billing (pricing-page promises). Reference, don't repeat.

## Inputs to gather first
- The core job-to-be-done in one sentence: from `.hardbuild.json → product.coreJob`, else README/landing hero, else infer from the primary nav and the first table in `supabase/migrations`.
- Route inventory: `find app -name 'page.tsx' | sed 's#/page.tsx##' | sort` (or `src/app`). Nav inventory: `grep -rnE "href=[\"'{]" components/**/nav* components/**/sidebar* app/**/layout.tsx`.
- Mutation inventory: server actions (`grep -rln '"use server"' app src`), route handlers (`find app -name route.ts`), client-side `supabase.from(...).insert|update|delete`.
- Browser access: `.hardbuild.json → audit.productionUrl` or a local `next dev` on :3000. Playwright present? `ls node_modules/.bin/playwright 2>/dev/null`.

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **PRD-01 · 3 · The core job is reachable in ≤3 clicks from the signed-in landing route.**
  VERIFY: walk it in a browser (Playwright or Chrome): sign in → count clicks to the screen where the job is *completed* (not started). Record the path as `/dashboard → /quotes/new → Submit (3)`. Else READ `app/(app)/layout.tsx` + nav component and trace `href`s to the page that owns the primary mutation.
  FAIL PATTERN: core action lives under Settings or a secondary tab; landing route is a marketing page for signed-in users; 4+ clicks or a required detour through a modal chain.
- **PRD-02 · 3 · The core job completes end to end with persisted data.**
  VERIFY: run the workflow once with a test account and confirm the row lands: Supabase MCP `select * from <core_table> order by created_at desc limit 1;` or check `.from('<core_table>').insert` is wired to the submit handler and the handler is actually called (`grep -rn "action={" app --include=*.tsx`). READ the primary server action: does it return success/redirect, or swallow errors?
  FAIL PATTERN: form posts to a stub `// TODO`, `console.log(data)`, or an action that returns `{ ok: true }` without writing.
- **PRD-03 · 2 · Onboarding / first-run gets a new user to first value.**
  VERIFY: create a fresh test user; what does `/` or the post-login redirect show when every table is empty? READ `app/**/onboarding*`, `middleware.ts` redirect logic, `profiles.onboarded`-style columns (`grep -rn "onboard" app src supabase/migrations`).
  FAIL PATTERN: new user lands on an empty dashboard with no next step; onboarding exists but `middleware.ts` never routes to it; onboarding cannot be skipped or resumed.
- **PRD-04 · 2 · Every list has a designed empty state.**
  VERIFY: `grep -rnE "\.length === 0|\.length > 0 \?|\?\.length \?|isEmpty" app components --include=*.tsx | wc -l` vs number of list pages; for each list component READ the zero branch — must render guidance + CTA, not `null` or an empty `<table>`.
  FAIL PATTERN: `{items.map(...)}` with no zero branch; "No data" string with no action; skeleton that never resolves when empty.
- **PRD-05 · 3 · No dead ends: every CTA does something.**
  VERIFY: `grep -rnE "href=[\"']#[\"']|onClick=\{\(\) => \{\}\}|onClick=\{\(\) =>\s*\}|href=\"\"|to=\"#\"" app components --include=*.tsx` → must be empty; `grep -rnE "TODO|coming soon|not implemented|WIP" app components --include=*.tsx -i`. In browser, click every button on the three primary screens.
  FAIL PATTERN: "Export" button with no handler; "Learn more" → `#`; disabled button with no explanation; link to a route with no `page.tsx`.
- **PRD-06 · 3 · Claim vs code: nav/marketing promises map to shipped features.**
  VERIFY: list every noun in nav labels, landing-page feature grid, and pricing tiers (`grep -rnE "<h[23]|title:" app/\(marketing\)/** app/page.tsx components/**/pricing*`). For each, cite the route + mutation that delivers it. Nav `href`s must resolve: `for p in $(grep -rhoE 'href="/[a-z0-9/_-]+"' app components | sort -u | tr -d '"' | sed 's/href=//'); do test -f "app$p/page.tsx" || echo "MISSING $p"; done` (adjust for route groups).
  FAIL PATTERN: pricing says "Team workspaces" but no `team_id` column exists; nav item routes to a 404; feature grid lists "AI summaries" with no AI call anywhere (`grep -rn "openai\|anthropic" --include=*.ts -il`).
- **PRD-07 · 2 · Feedback after every mutation.**
  VERIFY: for each server action/handler in the inventory, trace the caller: does it `toast(...)`, `redirect(...)`, `revalidatePath` + visible change, or set inline success? `grep -rnE "toast\.|useToast|sonner|revalidatePath|redirect\(" app components --include=*.ts* | wc -l` compared against mutation count. In browser, submit each primary form: visible confirmation within 1 s?
  FAIL PATTERN: form resets silently; delete removes row only after manual refresh; `router.refresh()` with no message; pending state missing (`useFormStatus`/`useTransition` absent → double submits).
- **PRD-08 · 2 · Search/filter exists where lists exceed ~20 items.**
  VERIFY: Supabase MCP `select relname, n_live_tup from pg_stat_user_tables order by 2 desc;` → for any table >20 rows surfaced in a list, the page must have a search/filter input (`grep -rnE "searchParams\.(q|query|search)|\.ilike\(|\.textSearch\(|\.range\(" app --include=*.ts*`). Else READ the list page for filter UI and `.range()`/`.limit()` pagination.
  FAIL PATTERN: `select('*')` renders all rows with no filter, sort, or pagination; filter is client-side only on a server-paginated set (results silently incomplete).
- **PRD-09 · 3 · Destructive actions are confirmable and recoverable.**
  VERIFY: `grep -rnE "\.delete\(\)|DELETE FROM|onDelete|handleDelete|deleteAction" app components lib --include=*.ts*` → each caller wraps in `AlertDialog`/`confirm(` *and* either soft-deletes (`deleted_at`, `archived`: `grep -rn "deleted_at\|archived_at" supabase/migrations`) or offers undo toast. Bulk deletes must confirm with the count.
  FAIL PATTERN: single-click hard delete on a row with child rows and `ON DELETE CASCADE`; "Delete account" with no cooling period; undo toast exists but the row is already gone from the DB.
- **PRD-10 · 2 · Analytics events fire on the key actions.**
  VERIFY: identify the provider (`grep -rnE "posthog|@vercel/analytics|track\(|capture\(|gtag\(|segment" --include=*.ts* -l app components lib`). For sign-up, core-job completion, upgrade/checkout, and invite, cite the `file:line` where the event fires. N/A if `.hardbuild.json → product.analytics: false` is explicit.
  FAIL PATTERN: `<Analytics />` pageviews only, zero custom events; events named inconsistently (`QuoteCreated` vs `quote_created`); events fired before the mutation succeeds.
- **PRD-11 · 2 · No roadmap debris reachable in the UI.**
  VERIFY: `grep -rnE "process\.env\.NEXT_PUBLIC_FEATURE_|featureFlags|isEnabled\(|flags\." app components --include=*.tsx`; `grep -rniE "beta|preview|experimental|soon" app components --include=*.tsx`. For each hit, confirm the feature is gated *and* the gate is off in prod, or it is finished. Routes that exist but are unlinked: compare route inventory to nav inventory.
  FAIL PATTERN: `/reports` page renders half a table with hardcoded mock data; "Beta" badge on a feature that throws; feature flag defaulting to `true` for an unfinished branch.
- **PRD-12 · 1 · Primary path survives a reload and the browser back button.**
  VERIFY: in browser, mid-way through the core flow press reload, then back. State should persist via URL (`searchParams`) or DB draft, not only `useState`. READ multi-step forms for `searchParams`/`localStorage`/draft-row usage.
  FAIL PATTERN: 4-step wizard loses everything on reload; back button exits the app instead of stepping back.
- **PRD-13 · 1 · Keyboard-first for the core action.**
  VERIFY: Enter submits the primary form; `autoFocus` on the first field of create screens (`grep -rn "autoFocus" app components --include=*.tsx`); a `⌘K`/command palette or shortcut exists if the app is used daily. Detail belongs to Accessibility — here just PASS/FAIL the core form.
  FAIL PATTERN: primary form uses `<div onClick>` instead of `<button type="submit">`; Enter in a search field does nothing.

## Scoring notes
- PRD-01, PRD-02, PRD-05, PRD-06, PRD-09 failing → CRITICAL (the core job doesn't work, or a promise is unbacked, or data can be destroyed without recourse); grade cap D.
- PRD-06 claim-vs-code findings are also noted in Copy & Content / Billing as the *promising* area; the engineering gap is counted once, here.
- Without a running app or production URL, PRD-01/02/05/07/12 can only be READ (conf 85) — never mark them PASS from code alone if the mutation chain couldn't be traced end to end; use INFERRED (50) and say what you could not trace.
- Without Supabase MCP, PRD-08 falls back to migrations + seed data and is INFERRED.
- "To raise confidence": a test account and `productionUrl` (or `next dev`) for PRD-01/02/03/05/07/12; Playwright installed for repeatable click-paths; Supabase MCP for PRD-02/08; the one-sentence core job from the owner if it had to be inferred.
