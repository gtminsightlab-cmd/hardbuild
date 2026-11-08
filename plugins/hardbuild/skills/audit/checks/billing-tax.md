# Billing & Tax audit — checks

**Purpose:** Verify billing and tax are implemented correctly — access changes only when Stripe says so, the app's record of who is paying matches Stripe's, no money is computed in floats, and tax is collected where the law requires it.
**Scorecard row:** Billing & Tax · **Report:** `audits/billing-tax.md` · **Overlaps:** Security (webhook signature headline SEC-08, secrets SEC-01), Identity & Access (plan gating as authorization), Branding (email look BRD-06/07), Legal (refund/tax/pricing claims), Test Coverage (E2E harness). Reference, don't repeat.

## Inputs to gather first
- Is there billing? `grep -E "\"stripe\"|@stripe/" package.json`; `.hardbuild.json → audit.billing` (`stripe` | `invoice-manual` | `none`). If `none` AND no Stripe dependency: every check is N/A ("no billing") and the area is excluded from the scorecard mean. If the dep exists but `billing=none`, that mismatch is itself a finding.
- Surface: `grep -rln "stripe" app src supabase/functions --include=*.ts --include=*.tsx`; webhook route (`app/api/stripe/webhook/route.ts` or `supabase/functions/stripe-webhook`); billing tables: `grep -rnE "create table[^(]*(subscription|customer|invoice|price|product|stripe_event|billing)" supabase/migrations`.
- `.hardbuild.json → audit.productionUrl`, `audit.taxMode` (`stripe-tax` | `manual` | `none`), `audit.gatedFeatures[]` (else derive from the pricing page).

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **BIL-01 · 3 · Stripe keys separated test/live by environment; live keys never reach preview.**
  VERIFY: `vercel env ls` (or Vercel MCP `filter_project_envs`) → `STRIPE_SECRET_KEY` scoped Production = `sk_live_`, Preview/Development = `sk_test_`; `STRIPE_WEBHOOK_SECRET` distinct per environment (each endpoint has its own `whsec_`). Repo: `git grep -nE "sk_(live|test)_[0-9a-zA-Z]{10,}|whsec_[0-9a-zA-Z]{10,}"` → empty. Only `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` (`pk_*`) appears in client code.
  FAIL PATTERN: one `sk_live_` set for "All environments" so preview deploys charge real cards.
- **BIL-02 · 3 · Webhook verifies the signature and is idempotent.**
  VERIFY: READ the handler: `const body = await req.text()` (raw, never `req.json()`), `stripe.webhooks.constructEvent(body, sig, secret)` in try/catch → 400 on failure; then an idempotency gate **before** any side effect — `insert into stripe_events (id, type, payload) values (...) on conflict (id) do nothing` and return 200 if zero rows, or an equivalent processed-id check. SQL: `select id, type, processed_at from stripe_events order by created_at desc limit 5;`. Local: `stripe listen --forward-to localhost:3000/api/stripe/webhook` then `stripe trigger invoice.paid` twice → second delivery logs "duplicate, skipped". Handler returns within 10s (defers heavy work).
  FAIL PATTERN: no `stripe_events` table; a retried `invoice.paid` grants two months of credit.
- **BIL-03 · 3 · Subscription state is mirrored to the DB from webhooks only — never from the client success redirect.**
  VERIFY: `grep -rnE "session_id|success_url|\?success=|checkout=success" app src --include=*.ts --include=*.tsx` → the success page may *read* (`checkout.sessions.retrieve`) to display, but must not write `subscriptions`/`profiles.plan`; all writes originate in the webhook for `checkout.session.completed`, `customer.subscription.{created,updated,deleted}`, `invoice.paid`, `invoice.payment_failed`. SQL: `select status, count(*) from subscriptions group by 1;` then spot-check 3 rows against `stripe subscriptions retrieve <sub_id>`.
  FAIL PATTERN: `/billing/success?plan=pro` server action flips the user to Pro on arrival — anyone can hit the URL.
- **BIL-04 · 3 · Entitlements enforced server-side on every gated feature.**
  VERIFY: for each gated feature, locate the server check — `grep -rnE "requirePlan\(|hasFeature\(|assertEntitled\(|subscription\.status|plan === " app src --include=*.ts --include=*.tsx` and classify each hit as server (route handler / server action / RLS policy using `subscriptions.status in ('active','trialing')`) or client-only. `curl -X POST <productionUrl>/api/<gated-route> -H "Cookie: <free-tier session>"` → 402/403.
  FAIL PATTERN: `{isPro && <ExportButton/>}` while `/api/export` has no plan check.
- **BIL-05 · 2 · Stripe Checkout and Customer Portal used; no hand-rolled card forms.**
  VERIFY: `grep -rnE "CardElement|PaymentElement|card_number|cardNumber|cvc|cvv" app src --include=*.tsx` → 0 for SaaS billing (Elements only with a documented reason); `checkout.sessions.create` and `billingPortal.sessions.create` present; portal configuration allows plan switch, cancel, payment-method update (`stripe billing_portal configurations list`). Keeps PCI scope at SAQ-A.
  FAIL PATTERN: custom card form posting the PAN to a server action.
- **BIL-06 · 2 · Prices and products referenced by ID from env/config; no hardcoded amounts.**
  VERIFY: `grep -rnE "price_[0-9A-Za-z]{10,}|prod_[0-9A-Za-z]{10,}" app src --include=*.ts --include=*.tsx | grep -vE "config|env|constants|plans\.ts"` → 0 inline IDs; `grep -rnE "unit_amount|amount: [0-9]{3,}" app src` → 0 (amounts live in Stripe). `lib/billing/plans.ts` maps plan → `process.env.STRIPE_PRICE_PRO_MONTHLY`, with different IDs per env. Pricing page renders from the same map; `stripe prices retrieve <id>` → `unit_amount` equals the displayed price (claim-vs-code).
  FAIL PATTERN: `$49/mo` in JSX, `price_1Abc…` in the button, `unit_amount: 4900` in a one-off session — three sources, drift guaranteed.
- **BIL-07 · 2 · Upgrade, downgrade, cancel, proration and refund paths handled and tested.**
  VERIFY: `grep -rnE "proration_behavior|cancel_at_period_end|subscriptions\.update\(|refunds\.create|charge\.refunded|credit_note" app src supabase/functions` → explicit choices; `cancel_at_period_end=true` keeps access until `current_period_end` (stored in DB); `customer.subscription.deleted` revokes; `charge.refunded` marks the invoice and applies the access decision. Refund policy on pricing/terms matches behaviour (→ Legal). Tests: `grep -rlE "subscription|refund" __tests__ tests e2e --include=*.test.* --include=*.spec.*`.
  FAIL PATTERN: cancel revokes immediately what the user paid for; refund issued in the dashboard, app still shows "Paid".
- **BIL-08 · 2 · Failed-payment dunning and a defined grace period.**
  VERIFY: Stripe dashboard → Settings → Subscriptions and emails: Smart Retries on, "Send emails when card payments fail" on, final action after retries chosen (ask for a screenshot). Code: `invoice.payment_failed` → `status='past_due'` + in-app banner + "update payment method" link to the Portal; `past_due` treated as active for N days (constant in `plans.ts`), then `unpaid`/`canceled` → revoke.
  FAIL PATTERN: `past_due` locks out instantly; or `past_due` is never handled and lapsed accounts stay active forever.
- **BIL-09 · 1 · Invoices and receipts reachable by the customer; billing emails on-brand.**
  VERIFY: `/billing` links to Portal invoice history, or lists `invoices` synced from `invoice.paid` with `hosted_invoice_url`/`invoice_pdf`; Stripe → Customer emails: successful payments + refunds on; Stripe → Branding: logo, icon, accent colour set and sender domain verified. Invoice footer carries legal name and address (→ Legal LGL-03). Template look detail is Branding BRD-06/07.
  FAIL PATTERN: customers email support for every receipt; grey default Stripe receipts beside a branded app.
- **BIL-10 · 3 · Tax: Stripe Tax enabled, or manual logic keyed by jurisdiction — never a hardcoded rate.**
  VERIFY: `grep -rnE "automatic_tax:\s*\{\s*enabled:\s*true" app src` on every Checkout/subscription create, plus `customer_update: { address: 'auto' }` or `tax_id_collection`; Stripe → Tax → registrations list matches states with nexus (SaaS is taxable in TX, NY, PA, WA, OH among others; generally not in CA, FL — the list must be deliberate). `grep -rnE "0\.0[0-9]{2,}\b|tax(Rate|_rate|Pct)\s*=|\* 1\.0[0-9]" app src --include=*.ts --include=*.tsx` → any literal rate is a finding. `taxMode=none` passes only with a written nexus analysis in `docs/`.
  FAIL PATTERN: `const TAX = 0.0825` — one Texas county rate applied to every customer in every state.
- **BIL-11 · 3 · Money in integer minor units; no floats.**
  VERIFY: `grep -rnE "price \* |\* 100\)|/ 100\b|parseFloat\(.*(price|amount|premium)|toFixed\(2\)|Number\(.*amount" app src supabase --include=*.ts --include=*.tsx` → every hit reviewed; `*100`/`/100` only at the display boundary inside one helper (`lib/money.ts`). SQL: `select table_name, column_name, data_type from information_schema.columns where table_schema='public' and column_name ~* 'amount|price|premium|total|balance|rate';` → `integer`/`bigint` (cents) or `numeric(12,2)`; `real`/`double precision` = FAIL. Dinero.js / `currency.js` / `BigInt` acceptable.
  FAIL PATTERN: `amount: Math.round(price * 100)` after `price` has been through `0.1 + 0.2`.
- **BIL-12 · 2 · Trials and coupon abuse controls.**
  VERIFY: `trial_period_days`/`trial_end` set server-side (never from client params); card-collection decision explicit (`payment_method_collection: 'always'` or a documented no-card trial); one trial per customer enforced (`profiles.trial_used_at` or Stripe customer metadata checked before `checkout.sessions.create`); promotion codes restricted — `stripe promotion_codes list --limit 20` → `max_redemptions`, `expires_at`, `restrictions.first_time_transaction` set.
  FAIL PATTERN: new email → new 14-day trial forever; `FRIENDS100` with no cap still live two years later.
- **BIL-13 · 2 · Audit trail of billing changes and a reconciliation job.**
  VERIFY: `stripe_events` retains `type`, `payload`, `processed_at` (not just ids): `select type, count(*) from stripe_events group by 1 order by 2 desc;`; plan changes write `audit_log(actor, before, after)`; a nightly job (`vercel.json` `crons` → `/api/cron/reconcile-billing`, or `pg_cron`) compares `subscriptions.status` to `stripe subscriptions list --status all` and reports drift. `select count(*) from subscriptions where status='active' and current_period_end < now() - interval '3 days';` → 0.
  FAIL PATTERN: 12 "active" rows whose period ended months ago; no record of who downgraded an account.
- **BIL-14 · 2 · Test-mode end-to-end of the purchase path exists and runs.**
  VERIFY: `ls e2e/**/*billing* e2e/**/*checkout* tests/**/*stripe*`; a Playwright spec that signs up, starts Checkout with `4242 4242 4242 4242`, returns, and asserts DB `status='active'` only *after* the webhook (CI runs `stripe listen` or `stripe trigger checkout.session.completed`), plus a `4000 0000 0000 0341` failed-payment case asserting `past_due`. Run it if the harness exists; else READ the spec and mark INFERRED.
  FAIL PATTERN: "we tested it manually once in March".

## Scoring notes
- BIL-01, 02, 03, 04, 10, 11 failing → CRITICAL (real charges from preview, double-crediting, free upgrades, uncollected tax = legal exposure, wrong amounts). BIL-07, 08, 13 → HIGH (revenue leakage). BIL-09/12 → MEDIUM.
- Whole-area N/A only when `billing=none` and no Stripe dep; never score an absent billing system 100.
- `taxMode=manual` can PASS BIL-10 only with a jurisdiction table plus registration evidence; a single rate is always FAIL.
- "To raise confidence": Stripe CLI with a restricted read key for BIL-02/05/06/08/12/13; Supabase SQL for BIL-02/03/11/13; Vercel env listing for BIL-01; a free-tier test session for BIL-04; a runnable E2E harness for BIL-14.
