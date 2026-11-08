# Branding audit — checks

**Purpose:** Check that branding is cohesive and consistent — one visual identity from the favicon to the password-reset email, so the product looks like one company built it on purpose.
**Scorecard row:** Branding · **Report:** `audits/branding.md` · **Overlaps:** Copy & Content (voice/tone, microcopy quality), UI/UX (component consistency, spacing), SEO (OG/meta correctness), Billing & Tax (Stripe-sent emails), Legal (footer entity/address). Reference, don't repeat.

## Inputs to gather first
- Brand token source: `tailwind.config.{js,ts}` `theme.extend.colors`, `app/globals.css` `:root` / `.dark` CSS vars, `components.json` (shadcn `cssVariables: true`).
- Brand name and domain: `.hardbuild.json → audit.brandName`, `audit.productionUrl`, `audit.emailDomain` (fall back to `package.json` name and `app/layout.tsx` metadata).
- Asset inventory: `ls app/icon.* app/apple-icon.* app/favicon.ico app/manifest.* app/opengraph-image.* app/twitter-image.* public/brand public/logo* 2>/dev/null`.
- Email templates: `supabase/templates/*.html` (Auth), `emails/` or `src/emails/` (react-email / Resend), edge functions that send mail.

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **BRD-01 · 2 · One source of truth for brand tokens; no stray hex in components.**
  VERIFY: `grep -rnoE "#[0-9a-fA-F]{6}\b" app src components --include=*.tsx --include=*.css | grep -v globals.css | wc -l` → target 0; list hits (`... | head -40`) and classify: duplicated brand colour (finding), one-off chart colour (note), third-party override with a comment (ok). Confirm `tailwind.config.*` colours point at CSS vars (`hsl(var(--primary))`) not literals, and `globals.css` defines each var once for `:root` and once for `.dark`.
  FAIL PATTERN: `className="bg-[#1E3A8A]"` sprinkled through pages while `--primary` is also defined; two slightly different blues in production.
- **BRD-02 · 2 · Logo is one component with correct variants.**
  VERIFY: `grep -rnE "<img[^>]*logo|logo[-_a-z]*\.(png|jpg|jpeg|svg)" app src components --include=*.tsx` → every hit should be a single `<Logo />` (e.g. `components/brand/logo.tsx`); READ it: inline SVG or `next/image` of an SVG, `variant` prop for full/mark/on-dark, `alt` = brand name (or `aria-hidden` when decorative beside text), responsive width (no fixed `width={240}` that overflows at 360px).
  FAIL PATTERN: three different logo PNGs in `public/`, one stretched, one with a white box on dark backgrounds.
- **BRD-03 · 2 · Favicon, app icons, manifest and OG image present and on-brand.**
  VERIFY: `ls app/icon.* app/apple-icon.* app/manifest.ts app/opengraph-image.* app/twitter-image.*`; `curl -sI <productionUrl>/icon` → 200 + `content-type: image/*`; `curl -s <productionUrl> | grep -oE '<meta property="og:[^>]+>'` → absolute `og:image` (1200×630), `og:title`, `og:description`; open the OG image and confirm it is the brand, not the Next.js default. `manifest.ts` `name`, `short_name`, `theme_color`, `background_color` equal the token values.
  FAIL PATTERN: Vercel triangle favicon still shipping; `og:image` 404 or pointing at `localhost:3000`.
- **BRD-04 · 2 · Product name spelled and cased one way everywhere.**
  VERIFY: build a variant regex from the brand name (e.g. `FastechHR|Fastech HR|FastTechHR|fastechhr|FASTECHHR`) then `grep -rnoiE "<variants>" app src components emails supabase/templates --include=*.tsx --include=*.ts --include=*.html --include=*.md | awk -F: '{print $NF}' | sort | uniq -c` → exactly one casing outside URLs/email addresses. Also check `package.json` name, `metadata.title`, manifest, email `from` display name, Stripe business name.
  FAIL PATTERN: "WorkComp Finder", "Workcompfinder" and "WorkCompFinder" in the same footer.
- **BRD-05 · 1 · Fonts loaded via `next/font`, limited to the brand set.**
  VERIFY: `grep -rnE "from ['\"]next/font" app src --include=*.tsx --include=*.ts` → one place (`app/layout.tsx` or `lib/fonts.ts`); `grep -rnE "fonts\.googleapis|@import url\(|font-family:" app src components --include=*.tsx --include=*.css | grep -v -- "--font-"` → 0 (no `<link>` Google Fonts, no raw `font-family` outside token definitions); distinct families ≤ 2 plus mono.
  FAIL PATTERN: Inter via next/font AND Roboto via `<link>` AND `font-family: Arial` in an email-style component.
- **BRD-06 · 2 · Email templates match the web brand.**
  VERIFY: READ `supabase/templates/*.html` (confirm, magic link, recovery, invite, email change) and confirm `supabase/config.toml [auth.email.template.*]` wires them; READ react-email templates. Each has logo (absolute https URL — `grep -n "src=\"http" supabase/templates/*.html`), brand colour on the CTA, brand name in header/footer, physical address footer (see Legal LGL-12). Untouched Supabase defaults = FAIL.
  FAIL PATTERN: plain-text "Confirm your signup" from `noreply@mail.app.supabase.io` with no logo.
- **BRD-07 · 2 · Transactional sender name and domain are on-brand and authenticated.**
  VERIFY: `dig TXT _dmarc.<emailDomain> +short` → `v=DMARC1; p=quarantine` or `p=reject`; `dig TXT resend._domainkey.<emailDomain> +short` (or the provider's selector) → DKIM present; `dig TXT <emailDomain> +short | grep spf` → includes the provider. READ the `from:` in send code → `"Brand <hello@brand.com>"`, never `onboarding@resend.dev`. Supabase Auth custom SMTP enabled (`config.toml [auth.email.smtp] enabled = true` or dashboard).
  FAIL PATTERN: DMARC `p=none` or absent; auth mail still from the provider's shared test domain.
- **BRD-08 · 1 · 404, error and empty states are on-brand.**
  VERIFY: `ls app/not-found.tsx app/error.tsx app/global-error.tsx`; READ each: uses tokens/fonts, shows logo or nav, offers a route home, brand voice (not "Application error: a client-side exception has occurred"). `curl -s -o /dev/null -w "%{http_code}" <productionUrl>/this-does-not-exist` → 404, then view it. Sample three list pages for empty states (`grep -rnE "No .* (found|yet)|Nothing here" --include=*.tsx app components`) → shared `<EmptyState>` component.
  FAIL PATTERN: Next.js default white 404; `global-error.tsx` missing so the root error page renders unstyled.
- **BRD-09 · 1 · Loading and splash states are on-brand.**
  VERIFY: `find app -name loading.tsx`; READ: skeletons use `bg-muted`/token colours, spinner is the shared brand component, no default third-party spinner GIF. `<meta name="theme-color">` (metadata `themeColor`) matches `--background`; manifest `background_color` so the installed-PWA splash matches.
  FAIL PATTERN: grey Bootstrap-style spinner; `theme-color` left `#000000`.
- **BRD-10 · 1 · Third-party widgets themed to the brand.**
  VERIFY: `grep -rliE "stripe|Elements|appearance|intercom|crisp|calendly|cal\.com|recaptcha|posthog.*survey" app src components --include=*.tsx`; Stripe Elements → `appearance: { variables: { colorPrimary, fontFamily } }`; Checkout/Customer Portal branding set in Stripe dashboard (logo, icon, accent — ask for a screenshot); chat/survey widgets pass colour in init options.
  FAIL PATTERN: Stripe purple default on a green-brand checkout.
- **BRD-11 · 1 · Voice and tone consistent across surfaces (headline only).**
  VERIFY: sample 5 strings each from marketing pages, app UI, auth emails and error messages; same person (we/you), same formality, same casing convention for buttons and headings (`grep -rnoE ">[A-Z][a-z]+ [A-Z][a-z]+<" app components --include=*.tsx | head` spots Title Case buttons where sentence case is the norm). Quality lives in Copy & Content; here only PASS/PARTIAL/FAIL consistency.
  FAIL PATTERN: playful marketing site, legalese app, robotic emails.
- **BRD-12 · 1 · Brand assets folder is organised.**
  VERIFY: `find public \( -iname "*logo*" -o -iname "*brand*" -o -iname "*icon*" \) | sort`; expect one folder (`public/brand/`) with named variants (`logo.svg`, `logo-mark.svg`, `logo-on-dark.svg`, `og.png`), no `logo-final-v3 (1).png`; `md5sum public/**/*.{png,svg} 2>/dev/null | sort | uniq -D -w32` → no duplicate bytes.
  FAIL PATTERN: six logo files at `public/` root, two identical, one unused.
- **BRD-13 · 2 · Metadata title template and defaults set.**
  VERIFY: READ `app/layout.tsx` `export const metadata`: `title: { default: 'Brand — tagline', template: '%s | Brand' }`, `metadataBase: new URL(productionUrl)`, `description`, `openGraph.siteName`, `icons`. `curl -s <productionUrl>/pricing | grep -o "<title>[^<]*"` → `Pricing | Brand`. Child pages export `title` as a plain string so the template applies.
  FAIL PATTERN: every page titled "Create Next App", or "Brand | Brand" from a child page repeating the brand.

## Scoring notes
- No CRITICAL checks by default; branding failures are HIGH at most. BRD-07 with DMARC absent on a domain sending auth mail is HIGH (deliverability, not just brand). Exception: an OG image, icon or email template that still carries a *different* company's brand (forked template) → CRITICAL, cross-reference Legal LGL-07.
- BRD-01 is PARTIAL when stray hex count is 1–10 and all are chart/one-off; FAIL above 10 or on any duplicated brand colour.
- BRD-04 is PARTIAL when the only variants are in URLs, email addresses or code identifiers; FAIL when two casings appear in user-visible text.
- With no production URL, BRD-03/08/13 are READ from `app/` (conf 85); `dig` for BRD-07 works without a deploy. Mark INFERRED only where the deployed asset itself cannot be confirmed.
- "To raise confidence": production URL for curl checks; DNS egress for BRD-07; Stripe dashboard access or screenshot for BRD-10; Supabase dashboard for custom-SMTP confirmation in BRD-07.
