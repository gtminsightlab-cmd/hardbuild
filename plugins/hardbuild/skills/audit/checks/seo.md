# SEO audit — checks

**Purpose:** Improve discoverability and shareability: search engines and AI answer engines can find, index, understand, and correctly attribute the public pages, and every shared link unfurls properly.
**Scorecard row:** SEO (and AI/answer-engine readiness) · **Report:** `audits/seo.md` · **Overlaps:** Performance (Core Web Vitals — measured there, referenced here), Landing Page (hero copy and CTA), Copy & Content (title/description wording), Accessibility (alt text, heading semantics). Reference, don't repeat.

## Inputs to gather first
- Public route inventory: `app/**/page.tsx` outside authenticated route groups (marketing, pricing, blog/docs, legal), plus `app/sitemap.ts`, `app/robots.ts`, `app/manifest.ts`, `app/opengraph-image.*`, `next.config.*` (`redirects()`, `headers()`, `i18n`).
- `.hardbuild.json → audit.productionUrl` (required for VERIFIED on crawl checks; without it everything is READ at best) and `audit.primaryCta` for message consistency.
- Private/app routes are out of scope except to confirm they are `noindex` (SEO-09).

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **SEO-01 · 3 · Every public route has unique, right-sized metadata via the Next Metadata API.**
  VERIFY: `grep -rLn "export const metadata\|export async function generateMetadata" $(find app -name page.tsx -not -path "*/(app)/*" -not -path "*/(dashboard)/*" -not -path "*/admin/*")` → public pages with neither are findings. For each with metadata, READ title (≤ 60 chars after the template suffix) and description (70–160 chars); `grep -rn "title:" app --include=page.tsx --include=layout.tsx | sort -t: -k3 | uniq -d -f2` to catch duplicates. With a URL: `for p in / /pricing /features; do curl -s <productionUrl>$p | grep -oE "<title>[^<]*</title>|<meta name=\"description\" content=\"[^\"]*\""; done`.
  FAIL PATTERN: root `layout.tsx` title `"Create Next App"` or one template used for every page; descriptions missing on `/pricing` and `/features`.
- **SEO-02 · 2 · Canonical URLs are set and consistent.**
  VERIFY: READ `metadataBase` in root layout (`new URL(process.env.NEXT_PUBLIC_SITE_URL)`) and `alternates.canonical` per route; `curl -s <productionUrl>/pricing | grep -o '<link rel="canonical"[^>]*>'` → absolute, https, matches the final URL (no trailing-slash or `www` mismatch). `curl -sI http://<host>` and `https://www.<host>` → 301 to one canonical origin.
  FAIL PATTERN: `metadataBase` missing so OG URLs render as `localhost:3000`; both `www` and apex serve 200 with different canonicals.
- **SEO-03 · 3 · `robots.txt` and `sitemap.xml` exist and are correct for production.**
  VERIFY: `curl -s <productionUrl>/robots.txt` → no `Disallow: /` for `*` in production; private groups (`/dashboard`, `/api`, `/auth`) disallowed; `Sitemap: <productionUrl>/sitemap.xml` line present. `curl -s <productionUrl>/sitemap.xml | grep -c "<loc>"` → count ≈ number of public routes, every `<loc>` absolute and returning 200 (`curl -s .../sitemap.xml | grep -oP '(?<=<loc>)[^<]+' | xargs -I{} curl -s -o /dev/null -w "%{http_code} {}\n" {}`). Else READ `app/robots.ts`/`app/sitemap.ts`: sitemap must enumerate dynamic routes (blog slugs from the DB) with `lastModified`.
  FAIL PATTERN: `robots.ts` returns `disallow: '/'` gated on `VERCEL_ENV !== 'production'` but the env var check is inverted; sitemap hard-codes three URLs while 40 blog posts exist; Vercel preview deployment URL leaked into the sitemap.
- **SEO-04 · 2 · Open Graph and Twitter cards render on share.**
  VERIFY: `curl -s <productionUrl> | grep -oE '<meta (property="og:|name="twitter:)[^>]*>'` → `og:title`, `og:description`, `og:image` (absolute, 1200×630), `og:url`, `og:type`, `twitter:card=summary_large_image`. `curl -sI <og:image url>` → 200 and `content-type: image/*`. READ `app/opengraph-image.tsx` (or static `opengraph-image.png`) exists at root and on key marketing segments; per-post dynamic OG images for blog/docs.
  FAIL PATTERN: `og:image` relative path; image is the favicon; no OG on `/pricing` so Slack/LinkedIn unfurls show nothing.
- **SEO-05 · 2 · Structured data (JSON-LD) present and valid.**
  VERIFY: `curl -s <productionUrl> | grep -oE '<script type="application/ld\+json">.*?</script>' | head -c 3000` → `Organization` (name, url, logo, sameAs, contactPoint) on home; `SoftwareApplication`/`Product` with `offers` on pricing/product pages; `FAQPage` where an FAQ exists; `BreadcrumbList` on nested pages; `Article` on blog posts. Validate: paste into `https://validator.schema.org/` or run `npx structured-data-testing-tool --url <productionUrl>` if available. READ fallback: `grep -rn "application/ld+json\|@type" app components`.
  FAIL PATTERN: JSON-LD with `"price": "Contact us"` (invalid type); FAQ schema whose questions do not appear visibly on the page (policy violation).
- **SEO-06 · 2 · Heading hierarchy: one H1 per page, logical order.**
  VERIFY: `curl -s <productionUrl>/<route> | grep -oE "<h[1-6][^>]*>" | sort | uniq -c` per public route → exactly one `<h1>`, no jumps from h2 to h4. READ fallback: `grep -rn "<h1" app components --include=*.tsx` → shared layout/header components that render an `<h1>` logo are findings.
  FAIL PATTERN: `<h1>` on the logo in the nav plus another in the hero; feature cards each wrapped in `<h1>` for styling.
- **SEO-07 · 2 · Internal linking from the landing page to every key public page.**
  VERIFY: `curl -s <productionUrl> | grep -oE 'href="/[^"#?]*"' | sort -u` → must include pricing, features/product, docs or how-it-works, blog (if any), contact, legal pages; compare to sitemap list and name orphans (pages in sitemap with zero inbound `href`). Links use `<Link href>` (crawlable `<a>`), not `onClick={() => router.push()}` buttons.
  FAIL PATTERN: pricing reachable only from a JS-driven modal; case-study pages with no inbound links.
- **SEO-08 · 2 · Indexability: marketing pages indexable, app pages noindex.**
  VERIFY: `curl -sI <productionUrl>/ | grep -i "x-robots-tag"` → absent or `index,follow` on marketing; `curl -s <productionUrl>/ | grep -i 'name="robots"'` → no `noindex`. For `/dashboard`, `/login`, `/app/*`: `noindex` via `metadata.robots` in the private layout or `X-Robots-Tag` in `next.config` headers. Vercel preview URLs set `X-Robots-Tag: noindex` automatically; confirm the production domain is not treated as preview (Deployment Protection off for production).
  FAIL PATTERN: `robots: { index: false }` copied from a template into the root layout; Vercel password protection left on production.
- **SEO-09 · 2 · Core Web Vitals are passing on public pages (reference Performance).**
  VERIFY: pull LCP/INP/CLS for `/` and `/pricing` from the Performance audit (`npx lighthouse <productionUrl> --only-categories=performance,seo --preset=desktop --output=json --quiet | jq '.categories.seo.score, .audits."largest-contentful-paint".numericValue'`). Lighthouse SEO category ≥ 0.9 and LCP < 2.5 s → PASS. Do not re-run the full performance suite here; cite the Performance report.
  FAIL PATTERN: hero image `<img>` without `next/image` `priority`; LCP 4.8 s on mobile.
- **SEO-10 · 2 · 404 and redirect hygiene.**
  VERIFY: `curl -s -o /dev/null -w "%{http_code}" <productionUrl>/this-does-not-exist` → 404 (not 200 soft-404, not 500); `app/not-found.tsx` exists with navigation back. READ `next.config.*` `redirects()`: each legacy path → final destination with `permanent: true`, no chains (`curl -sIL <productionUrl>/old-path | grep -c "^HTTP"` → ≤ 2 hops), no redirect loops; trailing-slash setting consistent (`trailingSlash`).
  FAIL PATTERN: `/features` → `/product` → `/platform` chain; `not-found.tsx` returns 200 via a catch-all page.
- **SEO-11 · 2 · AI crawler policy is deliberate; `llms.txt` present.**
  VERIFY: `curl -s <productionUrl>/robots.txt | grep -iE "GPTBot|ClaudeBot|Claude-Web|anthropic-ai|PerplexityBot|Google-Extended|CCBot|Bytespider|Applebot-Extended"` → an explicit Allow/Disallow decision per bot (allowing answer engines on marketing/docs is usually right for a B2B SaaS that wants to be recommended; disallowing training-only bots like `CCBot`/`Google-Extended` is a legitimate choice — the finding is *silence*, not either choice). `curl -s <productionUrl>/llms.txt` → 200, Markdown with a one-paragraph product summary and links to pricing, docs, and key pages; optional `llms-full.txt`. READ `app/robots.ts` rules array and `public/llms.txt`.
  FAIL PATTERN: no mention of any AI user agent; `llms.txt` missing on a product that wants to show up in "best workers' comp rater" answers.
- **SEO-12 · 1 · hreflang / locale handling if i18n is enabled.**
  VERIFY: N/A if single-locale (state so). Else `curl -s <productionUrl> | grep -o '<link rel="alternate" hreflang[^>]*>'` → one per locale plus `x-default`, reciprocal across locale pages; `metadata.alternates.languages` set; locale not detected solely by `Accept-Language` redirect that hides content from crawlers.
  FAIL PATTERN: `/es` pages exist but no hreflang, so Google treats them as duplicates.
- **SEO-13 · 1 · Images have descriptive alt text and filenames.**
  VERIFY: `grep -rnE "<Image|<img" app components --include=*.tsx | grep -vE 'alt=\{?"[^"]{3,}' | grep -v 'alt=""' ` → informative images without alt are findings (decorative ones must use `alt=""`); `ls public/**/*.{png,jpg,webp,svg} 2>/dev/null | grep -E "IMG_[0-9]+|Screenshot|image[0-9]*\.|untitled"` → non-descriptive filenames. Accessibility owns the WCAG angle; here it is about image search and context.
  FAIL PATTERN: `alt="image"` on every screenshot; `public/Screenshot 2025-03-04 at 10.12.31.png` as the hero.
- **SEO-14 · 1 · Search Console / Bing Webmaster verification present.**
  VERIFY: `curl -s <productionUrl> | grep -oE 'name="(google-site-verification|msvalidate.01)"[^>]*>'` or READ `metadata.verification.google`/`other['msvalidate.01']` in root layout, or a `public/google*.html` file, or a DNS TXT record (`dig TXT <host> +short | grep -i google-site-verification`). Sitemap submitted (ask the owner or check Search Console screenshot).
  FAIL PATTERN: no verification anywhere, so nobody can see indexing errors or manual actions.

## Scoring notes
- SEO-03 with `Disallow: /` or a blocked sitemap in production, and SEO-08 with `noindex` on marketing pages → CRITICAL (the product is invisible; grade cap D). SEO-01 missing on home/pricing → HIGH.
- Without `productionUrl`, every crawl check downgrades to READ (conf 85) from `app/robots.ts`, `app/sitemap.ts`, and metadata exports; mark SEO-08/10/14 INFERRED (50) when deployment behavior (Vercel protection, DNS) cannot be observed.
- Lighthouse SEO score alone never PASSes a check; use it as supporting evidence for SEO-01/06/09.
- "To raise confidence": production URL with no Deployment Protection; Vercel MCP `get_project`/`list_project_domains` for redirect and protection settings; Search Console access or export for index coverage; a Lighthouse run from the Performance audit.
