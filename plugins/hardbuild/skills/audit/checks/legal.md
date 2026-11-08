# Legal audit — checks

**Purpose:** Review terms, licenses, and required legal pages — the product makes no promise it cannot keep, records the consent it relies on, uses only code and assets it is licensed to use, and carries the disclosures a US insurance-adjacent SaaS must carry.
**Scorecard row:** Legal · **Report:** `audits/legal.md` · **Overlaps:** Privacy (policy content, data rights, subprocessors), Copy & Content (guarantee language), Billing & Tax (refund/tax/pricing claims), Dependencies (vulns — here only licences), Accessibility (statement vs reality). Reference, don't repeat. This audit is not legal advice: flagged fixes say "confirm with counsel".

## Inputs to gather first
- Legal pages: `ls -d app/{terms,privacy,legal,cookies,cookie-policy,accessibility,dpa,acceptable-use,licenses}* 2>/dev/null`; `grep -rhoE "href=\"/(terms|privacy|legal|cookies|dpa|accessibility|licenses)[^\"]*\"" app components --include=*.tsx | sort -u`.
- Entity facts from `.hardbuild.json → audit.legalEntity` (`name`, `address`, `email`, `state`, `producerLicenses[]`) — else from the footer; `audit.ugc`, `audit.marketingEmail`, `audit.sms`, `audit.repoPublic` (booleans), `audit.targetMarkets`.
- Consent columns: `grep -rnE "tos|terms_accepted|privacy_accepted|consent" supabase/migrations`.

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **LGL-01 · 3 · Terms of Service and Privacy Policy exist, render, and are linked in the footer and at signup.**
  VERIFY: `for p in terms privacy; do curl -s -o /dev/null -w "$p %{http_code}\n" <productionUrl>/$p; done` → 200 (not a redirect home); READ the signup form (`grep -rnE "agree|Terms|Privacy" app/\(auth\) components/auth --include=*.tsx`) → a checkbox, or "By creating an account you agree to the Terms and Privacy Policy" with links, above the submit button; footer component with both links is in every layout (marketing and app). A Cookie Policy is required only if non-essential cookies/trackers load (→ Privacy PRV-06).
  FAIL PATTERN: `/terms` is a generator placeholder with `[Company Name]`; signup never mentions terms.
- **LGL-02 · 2 · Legal pages are dated and versioned; material changes are notified.**
  VERIFY: `grep -rnE "Last updated|Effective" app/terms app/privacy` → a real date; a shared constant (`lib/legal.ts: export const TOS_VERSION = '2026-03-01'`) used by both the page and the acceptance write (LGL-04); a notification path (email on version bump, or re-accept gate).
  FAIL PATTERN: "Last updated: [DATE]" literally; terms edited in git with no version change.
- **LGL-03 · 2 · Legal name, address and contact consistent across every legal surface.**
  VERIFY: `grep -rhoE "[A-Z][A-Za-z0-9&' ]+ (LLC|Inc\.?|Corp\.?|L\.P\.|Ltd\.?)" app components emails supabase/templates --include=*.tsx --include=*.html | sort | uniq -c` → one entity string; repeat for the street address and `legal@`/`privacy@` email; Stripe `business_profile.name` and invoice footer match (`stripe accounts retrieve`); governing-law clause names the entity's state.
  FAIL PATTERN: footer says the holding company, Terms say the operating LLC, Stripe invoices say the brand name only.
- **LGL-04 · 3 · Acceptance recorded per user with version and timestamp.**
  VERIFY (SQL): `select table_name, column_name from information_schema.columns where table_schema='public' and column_name ~* 'tos|terms|privacy|accept|consent';` → `tos_accepted_at timestamptz` + `tos_version text` on the user/profile row, or a `consents(user_id, document, version, accepted_at, ip, user_agent)` table; `select count(*) filter (where tos_accepted_at is null), count(*) from profiles;` → 0 nulls. Code: the signup action writes it in the same transaction as the user row; middleware re-prompts when `tos_version <> TOS_VERSION`.
  FAIL PATTERN: checkbox exists, nothing is stored — the agreement is unenforceable.
- **LGL-05 · 3 · Dependency licences compatible with a proprietary SaaS.**
  VERIFY: `npx license-checker --production --summary`; then `npx license-checker --production --excludePrivatePackages --onlyAllow "MIT;ISC;BSD-2-Clause;BSD-3-Clause;Apache-2.0;0BSD;CC0-1.0;Unlicense;Python-2.0;BlueOak-1.0.0;MPL-2.0"` → exit 0. Any `GPL`, `AGPL`, `SSPL`, `LGPL` (bundled into the client), `CC-BY-NC`, `UNKNOWN`, `UNLICENSED`, or `SEE LICENSE IN` is a finding naming the package. Check `patches/` and `lib/vendor/` for copied code without headers.
  FAIL PATTERN: an AGPL PDF or charting library in the client bundle; `UNKNOWN` licences never reviewed.
- **LGL-06 · 2 · Fonts, icons, images and third-party data licensed for commercial use.**
  VERIFY: `next/font/google` (OFL) PASS; `ls public/fonts` → a licence file beside any self-hosted commercial font; `grep -E "lucide-react|@heroicons|react-icons|@radix-ui/react-icons|@fortawesome" package.json` (lucide ISC / heroicons MIT fine; Font Awesome Pro needs a seat); images: `find public -iregex ".*\.\(jpg\|jpeg\|png\|webp\)" | wc -l` with a `public/CREDITS.md` or `ATTRIBUTIONS.md` naming source and licence for stock/AI-generated art; datasets (NCCI class codes and descriptions, state rate filings, FMCSA extracts) have a documented usage right in `docs/`.
  FAIL PATTERN: stock comps with the watermark cropped; NCCI class descriptions reproduced verbatim without a licence.
- **LGL-07 · 1 · Trademark use correct — no competitor marks or logos, proper ™/® on own marks.**
  VERIFY: `grep -rnoiE "\b(workcompare|applied epic|vertafore|ezlynx|zywave|hawksoft|nowcerts|appulate)\b" app components --include=*.tsx` → mentions only in nominative comparison with "trademarks of their respective owners"; own brand uses ™ (® only if registered — check USPTO TSDR for the entity); `find public -iname "*<competitor>*"` → nothing.
  FAIL PATTERN: "WorkCompare-style" in product copy without attribution; ® on an unregistered mark.
- **LGL-08 · 3 · Insurance disclosures: producer/agency licence information where the product solicits, quotes or binds.**
  VERIFY: if `producerLicenses[]` is non-empty → footer or `/licenses` page lists legal name, NPN, resident-state licence number and each non-resident state (CA requires the CA licence number in advertising; TX requires the agency name as licensed) — `grep -rnE "NPN|License ?#|Lic\.? ?#|CA Lic" app components --include=*.tsx`. If the product is software used *by* producers (rater, agency tool), an explicit "not an insurer or licensed producer; does not sell, solicit or negotiate insurance" statement on marketing pages and in Terms. Confirm per state with counsel.
  FAIL PATTERN: "Get a quote" CTA on every page with no licensee named anywhere.
- **LGL-09 · 3 · No coverage or outcome guarantees; indications labelled as indications.**
  VERIFY: `grep -rnoiE "guarantee[ds]?|guaranteed (savings|coverage|approval|rate)|lowest (rate|price)|will (save|cover|approve)|bound quote|instant coverage|you'?re covered" app components emails --include=*.tsx --include=*.html --include=*.md` → each hit reviewed; every rater/indication output (screen, PDF, email) carries "Premium indication only — not a quote, binder or offer of coverage. Final premium subject to carrier underwriting, audit and filed rates." plus the rate/data effective date — `grep -rn "indication" components/quote* app/**/quote* lib/pdf`. Wording quality lives in Copy & Content; here it is E&O exposure.
  FAIL PATTERN: "Your WC premium: $4,812 — guaranteed" on a comparative-rater result.
- **LGL-10 · 2 · DMCA/abuse contact and Acceptable Use if users can post content (N/A if no UGC).**
  VERIFY: if `audit.ugc` (shared uploads, public profiles, directory listings, comments): `/dmca` or a DMCA section in Terms naming a designated agent registered at `dmca.copyright.gov` (ask for confirmation); `abuse@`/`legal@` mailbox resolves (`dig MX <domain> +short`); Acceptable Use clause in Terms; a takedown path in the admin UI.
  FAIL PATTERN: a business directory built from user submissions with no takedown route.
- **LGL-11 · 2 · Accessibility statement exists and matches reality.**
  VERIFY: `/accessibility` page states target (WCAG 2.1 or 2.2 AA), known limitations, feedback contact; compare with the Accessibility area score — a conformance claim while that area is < 80 is a claim-vs-code finding here. ADA Title III demand letters hit B2B SaaS too.
  FAIL PATTERN: "fully WCAG compliant" alongside 40 contrast failures.
- **LGL-12 · 3 · Email and SMS compliance (CAN-SPAM, TCPA).**
  VERIFY: if `audit.marketingEmail`: every marketing template has a physical postal address and a working unsubscribe (`grep -rnE "unsubscribe|List-Unsubscribe" emails supabase/functions`); `List-Unsubscribe` + `List-Unsubscribe-Post` headers set by the provider; a suppression check before send (`grep -rnE "suppress|unsubscribed_at" app src supabase/functions`) honoured within 10 business days. Transactional mail (auth, receipts) is exempt but still identifies the sender. If `audit.sms`: prior express written consent captured with the disclosure text ("Msg & data rates may apply. Reply STOP to cancel") and stored (`sms_consent_at`, source), STOP handled, 8am–9pm recipient-local quiet hours enforced, 10DLC campaign registered (ask).
  FAIL PATTERN: Resend broadcast with no address; SMS reminders to numbers pulled from FMCSA records with no consent.
- **LGL-13 · 2 · DPA / data-processing terms available to B2B customers.**
  VERIFY: `/dpa` page or "Data Processing Addendum available on request" in Terms, with a subprocessor list (→ Privacy PRV-11) and security commitments matching the Security area — no "SOC 2 certified" unless `ls docs/compliance/*soc2*` exists. For PEO/payroll/claims data, Terms allocate roles (controller/processor, or business/service provider under CPRA) and name the customer as data owner.
  FAIL PATTERN: Terms silent on data processing while the product ingests payroll, census and loss runs.
- **LGL-14 · 1 · Repository LICENSE matches intent (N/A if the repo is private and never shared).**
  VERIFY: `audit.repoPublic` → `ls LICENSE*`; `jq -r '.license, .private' package.json` → `UNLICENSED` + `true` for proprietary, or a real SPDX id for open source; no starter-template MIT `LICENSE` left on commercial code.
  FAIL PATTERN: public repo carrying the Vercel starter's MIT licence and `"license": "MIT"` on a paid product.

## Scoring notes
- LGL-01, 04, 05 (copyleft in the bundle), 08, 09, 12 failing → CRITICAL (unenforceable terms, licence breach, unlicensed solicitation, E&O exposure, per-message statutory penalties). LGL-03, 11, 13 → HIGH.
- Every legal finding's fix text ends with "confirm with counsel"; the audit locates the gap (file:line / URL), it does not opine on the law.
- Claim-vs-code is the main lens: a legal page that promises something (SOC 2, GDPR, encryption, 30-day refunds) engineering does not deliver is a finding *here* with a note in the engineering area.
- "To raise confidence": production URL for LGL-01/11; Supabase SQL for LGL-04; network for `license-checker` (LGL-05) and `dig` (LGL-10/12); owner/counsel confirmation for producer licences (LGL-08), DMCA agent registration (LGL-10), 10DLC registration (LGL-12).
