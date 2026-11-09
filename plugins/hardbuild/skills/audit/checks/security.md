# Security audit — checks

**Purpose:** Find ways an attacker, a curious user, or a careless deploy could read, change, or destroy data, or run code they shouldn't.
**Scorecard row:** Security · **Report:** `audits/security.md` · **Overlaps:** Identity & Access (auth/RLS detail), Dependencies (vulnerable packages), Privacy (data exposure). Reference, don't repeat.

## Inputs to gather first
- Surface inventory: API routes (`route.ts`), server actions (`"use server"`), middleware, Supabase tables + policies, edge functions, env vars.
- `.hardbuild.json → audit.productionUrl` for header checks (skip URL checks as N/A if empty).

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **SEC-01 · 3 · No secrets in the repo or client bundle.**
  VERIFY: `git grep -nE "(sk_live_|sk_test_|service_role|SUPABASE_SERVICE_ROLE|eyJhbGciOi|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|PRIVATE))" -- ':!*.md' ':!.env.example'` → must be empty; `git log -p --all -S 'service_role' --oneline | head` for history leaks; check that only `NEXT_PUBLIC_*` vars are referenced in client components (`grep -rn "process.env" --include=*.tsx | grep -v NEXT_PUBLIC`).
  FAIL PATTERN: service-role key used in a `"use client"` file or exposed through `NEXT_PUBLIC_`.
- **SEC-02 · 3 · Service-role Supabase client is server-only.**
  VERIFY: grep for `createClient(` with `SUPABASE_SERVICE_ROLE_KEY`; each file must be a server action, route handler, or `server-only` module (`import 'server-only'`) and never imported from a client component.
- **SEC-03 · 3 · Every write path validates input.**
  VERIFY: for each route handler/server action in the inventory, open it; confirm a schema parse (`zod` `.parse/.safeParse`) or equivalent before use of `body`/`formData`/params. Cite `file:line` for each miss.
  FAIL PATTERN: `const body = await req.json(); await supabase.from('x').insert(body)`.
- **SEC-04 · 3 · Every write path checks auth and authorization.**
  VERIFY: same files — `supabase.auth.getUser()` (not `getSession()` on the server) or middleware guard, plus an ownership/tenant check or RLS reliance that is actually enabled (see IAM). Cite misses.
- **SEC-05 · 3 · RLS enabled on all public tables with non-permissive policies.**
  VERIFY (Supabase MCP if available): `select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and relkind='r';` → all `true`; `select * from pg_policies where schemaname='public';` → no `USING (true)` on write policies. Else READ migrations: `grep -rn "enable row level security\|create policy" supabase/migrations`. Full detail belongs in Identity & Access; here just PASS/FAIL the headline.
- **SEC-06 · 2 · Security headers set.**
  VERIFY: `curl -sI <productionUrl>` → `strict-transport-security`, `x-content-type-options: nosniff`, `x-frame-options` or CSP `frame-ancestors`, `referrer-policy`, a `content-security-policy` (even report-only). Else READ `next.config.*` `headers()` or `middleware.ts`.
- **SEC-07 · 2 · Rate limiting / abuse controls on public endpoints.**
  VERIFY: for unauthenticated POST routes (contact, signup, quote, webhook, AI calls) look for `@upstash/ratelimit`, Vercel WAF/firewall rules, Supabase auth rate limits, or captcha. Cite each unprotected public write.
- **SEC-08 · 3 · Webhooks verify signatures.**
  VERIFY: each webhook route (Stripe, Supabase, Resend, Clerk…) reads the raw body and calls the provider's `constructEvent`/HMAC verify before acting; cite line. Idempotency on event id.
- **SEC-09 · 2 · No injection vectors.**
  VERIFY: `grep -rnE "\.rpc\(|sql\`|\.raw\(|dangerouslySetInnerHTML|eval\(|new Function\(" --include=*.ts --include=*.tsx` → each hit reviewed; string-built SQL or unsanitized HTML = finding. Supabase `.or()`/`.filter()` built from user strings is a finding.
- **SEC-10 · 2 · File uploads are constrained.**
  VERIFY: Supabase Storage bucket policies (public vs private), size/MIME limits, path built from user id not user input, signed URLs for private files. N/A if no uploads.
- **SEC-11 · 2 · Redirects and CORS are safe.**
  VERIFY: any `redirect(searchParams.next)` style open-redirect must whitelist; `Access-Control-Allow-Origin: *` on authenticated routes is a finding; Supabase Auth redirect allow-list matches real URLs.
- **SEC-12 · 2 · Error responses don't leak internals.**
  VERIFY: route handlers return generic messages to clients and log details server-side; stack traces/SQL errors never reach `NextResponse.json`. Cite leaks.
- **SEC-13 · 1 · Dependencies have no known critical vulns (headline only).**
  VERIFY: `pnpm audit --prod --audit-level=high` (or npm/yarn equivalent) → summary line. Detail lives in Dependencies.
- **SEC-14 · 1 · Secure cookies & session handling.**
  VERIFY: `@supabase/ssr` used for cookie-based sessions; `httpOnly`/`secure`/`sameSite` on any custom cookies; no tokens in `localStorage` by hand.

## Scoring notes
- SEC-01, 02, 04, 05, 08 failing → CRITICAL findings (grade cap D).
- With no production URL, SEC-06 can still be READ from config (conf 85); mark it INFERRED if config exists but you cannot confirm deployment.
- "To raise confidence": Supabase MCP access for SEC-05, production URL for SEC-06/11, `pnpm audit` network access for SEC-13.
