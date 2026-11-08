# Identity & Access audit — checks

**Purpose:** Verify auth and permissions are implemented correctly: sessions are trustworthy on the server, every private page and row is guarded, and no user can see or change another tenant's data.
**Scorecard row:** Identity & Access · **Report:** `audits/identity-access.md` · **Overlaps:** Security (headline RLS/auth checks SEC-04/05/14 — this file is the detail), Privacy (deletion/export obligations), Database (schema of `memberships`/`tenants`). Reference, don't repeat.

## Inputs to gather first
- Auth wiring: `grep -rln "@supabase/ssr" app lib utils src` → the browser client, server client, and middleware/proxy files.
- Route inventory: every `app/**/page.tsx` and `app/**/route.ts`, tagged public vs private from the nav and the product's intent (dashboard, quotes, submissions, admin).
- Tables and policies: Supabase MCP `select tablename, policyname, cmd, roles, qual, with_check from pg_policies where schemaname='public' order by tablename, cmd;` else `supabase/migrations/*.sql`.
- Auth settings: Supabase dashboard → Authentication → Providers/Settings/URL Configuration, or `supabase/config.toml` `[auth]` section when using CLI-managed config.
- `.hardbuild.json → audit.productionUrl` and, if given, two test logins (user A and user B in different tenants).

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **IAM-01 · 3 · `@supabase/ssr` cookie sessions are wired correctly.**
  VERIFY: `grep -rn "createServerClient\|createBrowserClient" app lib utils src` → exactly one browser factory, one server factory that is called per request (not a module-level singleton), and a `middleware.ts` (Next ≤15) or `proxy.ts` (Next 16) that calls `supabase.auth.getUser()` to refresh the session and writes cookies back to the response. READ the server factory: `cookies()` must be awaited (Next 15+) and `setAll` must handle the Server Component read-only case with try/catch.
  FAIL PATTERN: legacy `@supabase/auth-helpers-nextjs`; a server client created at module scope and shared across requests; middleware present but never calling `getUser()`, so tokens silently expire.
- **IAM-02 · 3 · Server code trusts `getUser()`, never `getSession()`.**
  VERIFY: `grep -rn "auth.getSession()" app lib utils src --include=*.ts --include=*.tsx | grep -v "use client"` → every hit in a server action, route handler, layout, or middleware is a finding (session is read from the cookie unverified). `getUser()` or `getClaims()` (verifies JWT signature) are acceptable.
  FAIL PATTERN: `const { data: { session } } = await supabase.auth.getSession(); if (!session) redirect('/login')` in `app/(app)/layout.tsx`.
- **IAM-03 · 3 · Protected routes are enforced server-side, and the matcher covers every private path.**
  VERIFY: READ `middleware.ts`/`proxy.ts` `config.matcher`; list private route groups from the inventory and diff against the matcher. Then for each private `page.tsx`/`layout.tsx` not covered, confirm an in-page `getUser()` guard. With a production URL: `curl -sI <productionUrl>/dashboard` (and `/admin`, `/quotes`, `/settings`) unauthenticated → expect 302/307 to login, not 200. List every private page lacking a guard with `file:line`.
  FAIL PATTERN: matcher is `['/dashboard/:path*']` but `/quotes`, `/reports`, `/api/export` ship unguarded; or the guard is a `"use client"` `useEffect` redirect that still renders data server-side.
- **IAM-04 · 3 · Authorization model is explicit and used consistently.**
  VERIFY: find the source of truth — either a custom access token hook (`select * from pg_proc where proname ilike '%access_token%'`; Dashboard → Auth → Hooks) stamping `app_metadata.role`/`tenant_id` into the JWT, or a `memberships`/`org_members` table with `(user_id, org_id, role)`. Then `grep -rn "role\b\|isAdmin\|tenant_id\|org_id" app lib --include=*.ts --include=*.tsx | head -60` → every authorization decision must read from that one source. Cite places that check `user.email.endsWith('@yourco.com')`, a hardcoded UUID list, or `user_metadata` (user-editable!) for role.
  FAIL PATTERN: role stored in `raw_user_meta_data`, which any user can update via `supabase.auth.updateUser()`.
- **IAM-05 · 3 · RLS: every public table has a policy per operation with a tenant/ownership predicate.**
  VERIFY (Supabase MCP): `select c.relname, c.relrowsecurity, c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' order by 1;` → all `relrowsecurity = true`. Then `select tablename, cmd, policyname, qual, with_check from pg_policies where schemaname='public' order by 1,2;` → build a table × {SELECT, INSERT, UPDATE, DELETE} matrix; each cell needs a policy whose `qual`/`with_check` references `auth.uid()`, `auth.jwt() ->> 'tenant_id'`, or a membership subquery. Also run `mcp__Supabase__get_advisors` (security) and quote its RLS findings. Else READ `supabase/migrations/*.sql`: `grep -n "create policy\|enable row level security\|using (\|with check (" supabase/migrations/*.sql`.
  FAIL PATTERN: `using (true)` on SELECT of `quotes`; INSERT policy with no `with check` so a user can insert rows for another `org_id`; tables created later than the "enable RLS everywhere" migration and forgotten.
- **IAM-06 · 3 · Admin and service-role paths are isolated from tenant paths.**
  VERIFY: `grep -rln "SUPABASE_SERVICE_ROLE_KEY" app lib utils supabase/functions` → each file is `import 'server-only'` or a route handler/server action/edge function; each call site re-checks the caller's admin role from IAM-04's source before acting. Admin UI lives under its own route group (`app/(admin)/`) with its own layout guard. Edge functions: READ `supabase/functions/*/index.ts` for `verify_jwt` and an explicit role check when using the service key.
  FAIL PATTERN: `/api/admin/*` routes authenticated by `getUser()` only (any logged-in user is "admin"); service client used for an ordinary tenant read "to avoid RLS problems".
- **IAM-07 · 2 · Password, OTP, and magic-link settings are hardened.**
  VERIFY: Dashboard → Authentication → Settings (or `supabase/config.toml` `[auth]`): minimum password length ≥ 8 (prefer 12) with a complexity requirement, leaked password protection (HaveIBeenPwned) ON, email confirmations ON (`enable_confirmations = true`), OTP/magic-link expiry ≤ 3600 s, OTP length ≥ 6. `grep -n "minimum_password_length\|otp_expiry\|enable_confirmations\|password_requirements" supabase/config.toml`.
  FAIL PATTERN: default 6-char passwords, email confirm off so any address can be claimed, 24 h OTP expiry.
- **IAM-08 · 2 · OAuth redirect allow-list is exact.**
  VERIFY: Dashboard → Authentication → URL Configuration: Site URL equals `productionUrl`; Redirect URLs list only real origins (production, preview wildcard like `https://*-team.vercel.app/**` if needed, `http://localhost:3000/**`). `grep -rn "redirectTo\|emailRedirectTo" app lib` → values derived from `NEXT_PUBLIC_SITE_URL`/`origin`, not from `searchParams`. `app/auth/callback/route.ts` validates `next` is a relative path before `redirect()`.
  FAIL PATTERN: `redirectTo: searchParams.get('next')` → open redirect post-login; `**` wildcard on the whole domain list.
- **IAM-09 · 2 · MFA is available and required for admin roles.**
  VERIFY: `grep -rn "mfa.enroll\|mfa.challenge\|aal2\|getAuthenticatorAssuranceLevel" app lib` → enrollment UI exists; admin RLS policies or the admin layout require `(auth.jwt() ->> 'aal') = 'aal2'`. N/A only if the product has no privileged role (state why).
  FAIL PATTERN: MFA toggled on in the dashboard but no enrollment screen and no `aal2` check anywhere.
- **IAM-10 · 2 · Session expiry, refresh, and logout actually invalidate.**
  VERIFY: Dashboard → Auth → Settings: JWT expiry ≤ 3600 s, refresh token rotation ON with reuse detection. `grep -rn "signOut(" app lib` → called from a server action or route handler with `scope: 'global'` where "log out everywhere" is offered, and cookies cleared via the SSR client. With a browser: log in, sign out, press back → protected page must redirect, not render from cache (check `Cache-Control: private, no-store` on private HTML via `curl -sI`).
  FAIL PATTERN: `signOut()` only on the browser client while server components keep serving the cached page; 1-week JWT expiry.
- **IAM-11 · 2 · Invitation and onboarding flows cannot escalate.**
  VERIFY: READ the invite path (`inviteUserByEmail`, `invitations` table, `/accept-invite` route): the inviter must be an admin of the *same* org (RLS `with check` on `invitations.org_id`), the invitee's resulting role is copied from the invitation row server-side, never from the client payload, and invitation tokens are single-use with an expiry. `grep -rn "role:" app --include=*.ts --include=*.tsx | grep -i "formData\|body\.\|searchParams"` → any client-supplied role is a finding.
  FAIL PATTERN: signup form posts `{ role: 'owner', org_id }` and the server inserts it as-is.
- **IAM-12 · 2 · Account deletion and data export paths exist and work.**
  VERIFY: `grep -rn "auth.admin.deleteUser\|deleteUser\|export" app lib supabase/functions | grep -vi "export const\|export default\|export function\|export async\|export type\|export interface"` → a self-service or support-triggered path that deletes the auth user *and* cascades or anonymizes tenant rows (`on delete cascade` in migrations: `grep -n "on delete" supabase/migrations/*.sql`). Legal/privacy obligations live in Privacy; here confirm the mechanism exists.
  FAIL PATTERN: "Delete account" button that only signs out; FK rows left orphaned with PII.
- **IAM-13 · 1 · Auth events are logged and reviewable.**
  VERIFY: Supabase MCP `mcp__Supabase__query_logs` (service `auth`) returns recent sign-in/failure events; app-side `grep -rn "SIGNED_IN\|onAuthStateChange\|PASSWORD_RECOVERY" app lib` and any `audit_log` table insert on role changes, invites, and deletions. Vercel runtime logs for 401/403 bursts.
  FAIL PATTERN: no record of who changed a user's role or when.
- **IAM-14 · 3 · Tenant isolation test: user A cannot read user B's rows.**
  VERIFY (strongest): with two test users and the anon key, `curl -s "<supabaseUrl>/rest/v1/<table>?select=id&limit=5" -H "apikey: <anon>" -H "Authorization: Bearer <userA_jwt>"` → only A's rows; repeat with `?id=eq.<B_row_id>` → `[]`; `curl -X PATCH ... ?id=eq.<B_row_id>` → 0 rows affected. Or in SQL via MCP: `set role authenticated; select set_config('request.jwt.claims', '{"sub":"<A_uuid>","role":"authenticated"}', true); select count(*) from <table>;` compared to a superuser count. Else READ the policies from IAM-05 and look for an automated test in `tests/`/`e2e/` (`grep -rln "rls\|tenant isolation\|cross-tenant" tests e2e`). No test and no policy evidence → FAIL.
  FAIL PATTERN: isolation enforced only by `.eq('org_id', orgId)` in application queries while RLS is permissive.

## Scoring notes
- IAM-02, 03, 04, 05, 06, 14 failing → CRITICAL (auth bypass or cross-tenant exposure; grade cap D, not ship-ready). IAM-01 failing is CRITICAL when it causes `getUser()` to receive stale/expired tokens on private pages.
- IAM-11 failing is CRITICAL if a self-signup user can become admin; otherwise HIGH.
- IAM-09 is N/A only for products with no admin/privileged role; a B2B insurance tool with an agency-admin or carrier-admin role is never N/A.
- Dashboard-only settings (IAM-07, 08, 10) are READ (conf 85) when inspected via dashboard screenshot or `config.toml`; INFERRED (50) if only defaults are assumed. Never PASS them unseen.
- "To raise confidence": Supabase MCP for IAM-05/13/14 (policy matrix, advisors, auth logs), two test logins in separate tenants for IAM-14, production URL for IAM-03/10 curl checks, dashboard access or `supabase/config.toml` for IAM-07/08/10.
