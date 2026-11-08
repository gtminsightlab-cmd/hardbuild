#!/usr/bin/env bash
# Phase 0 of every audit: detect the stack so checks are tailored, not generic.
# Prints a JSON object. Confidence per fact: "high" (file/dep present), "medium" (inferred).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
P="$(hb_project_dir)"; cd "$P" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || { echo '{"error":"jq not installed"}'; exit 0; }

dep() { hb_has_dep "$1" && echo true || echo false; }
has() { [ -e "$1" ] && echo true || echo false; }
ver() { jq -r --arg d "$1" '(.dependencies[$d] // .devDependencies[$d]) // ""' package.json 2>/dev/null; }

if [ ! -f package.json ]; then
  jq -n --arg pm "none" --argjson py "$(has pyproject.toml)" '{framework:"unknown",packageManager:$pm,python:$py,confidence:"medium"}'; exit 0
fi

APP_ROUTER=false; [ -d app ] || [ -d src/app ] && APP_ROUTER=true
PAGES_ROUTER=false; [ -d pages ] || [ -d src/pages ] && PAGES_ROUTER=true
MIGS=0; [ -d supabase/migrations ] && MIGS=$(ls supabase/migrations 2>/dev/null | wc -l | tr -d ' ')
EDGE=0; [ -d supabase/functions ] && EDGE=$(ls -d supabase/functions/*/ 2>/dev/null | wc -l | tr -d ' ')
TESTS=$(grep -rlE --include='*.test.*' --include='*.spec.*' --exclude-dir=node_modules --exclude-dir=.next '' . 2>/dev/null | wc -l | tr -d ' ')
E2E=$(find . -path ./node_modules -prune -o \( -path '*e2e*' -o -path '*playwright*' \) -name '*.ts' -print 2>/dev/null | head -50 | wc -l | tr -d ' ')
SRC_FILES=$(find . -path ./node_modules -prune -o -path ./.next -prune -o \( -name '*.ts' -o -name '*.tsx' \) -print 2>/dev/null | wc -l | tr -d ' ')
ROUTES=$(find . -path ./node_modules -prune -o -path ./.next -prune -o \( -name 'page.tsx' -o -name 'page.jsx' -o -name 'page.js' \) -print 2>/dev/null | wc -l | tr -d ' ')
API=$(find . -path ./node_modules -prune -o -path ./.next -prune -o -name 'route.ts' -print 2>/dev/null | wc -l | tr -d ' ')
ACTIONS=$(grep -rlE --include='*.ts' --include='*.tsx' --exclude-dir=node_modules --exclude-dir=.next "^['\"]use server['\"]" . 2>/dev/null | wc -l | tr -d ' ')

jq -n \
  --arg pm "$(hb_pm)" \
  --arg next "$(ver next)" --arg react "$(ver react)" --arg ts "$(ver typescript)" \
  --argjson appRouter "$APP_ROUTER" --argjson pagesRouter "$PAGES_ROUTER" \
  --argjson tailwind "$(dep tailwindcss)" --argjson shadcn "$(has components.json)" \
  --argjson supabaseJs "$(dep @supabase/supabase-js)" --argjson supabaseSsr "$(dep @supabase/ssr)" \
  --argjson supabaseDir "$(has supabase)" --argjson migrations "$MIGS" --argjson edgeFunctions "$EDGE" \
  --argjson vercelJson "$(has vercel.json)" --argjson vercelAnalytics "$(dep @vercel/analytics)" --argjson speedInsights "$(dep @vercel/speed-insights)" \
  --argjson stripe "$(dep stripe)" --argjson sentry "$(dep @sentry/nextjs)" --argjson posthog "$(dep posthog-js)" \
  --argjson nextIntl "$(dep next-intl)" --argjson i18next "$(dep i18next)" \
  --argjson zod "$(dep zod)" --argjson prisma "$(dep prisma)" --argjson drizzle "$(dep drizzle-orm)" \
  --argjson vitest "$(dep vitest)" --argjson jest "$(dep jest)" --argjson playwright "$(dep @playwright/test)" --argjson rtl "$(dep @testing-library/react)" \
  --argjson eslint "$(dep eslint)" --argjson prettier "$(dep prettier)" --argjson husky "$(dep husky)" \
  --argjson resend "$(dep resend)" --argjson nodemailer "$(dep nodemailer)" --argjson upstash "$(dep @upstash/ratelimit)" \
  --argjson tsconfig "$(has tsconfig.json)" --argjson strict "$( [ -f tsconfig.json ] && jq -r '.compilerOptions.strict // false' tsconfig.json || echo false)" \
  --argjson envExample "$(has .env.example)" --argjson envLocal "$(has .env.local)" --argjson middleware "$( { [ -f middleware.ts ] || [ -f src/middleware.ts ] || [ -f proxy.ts ] || [ -f src/proxy.ts ]; } && echo true || echo false)" \
  --argjson readme "$(has README.md)" --argjson license "$(has LICENSE)" --argjson ci "$(has .github/workflows)" \
  --argjson testFiles "$TESTS" --argjson e2eFiles "$E2E" --argjson srcFiles "$SRC_FILES" --argjson pages "$ROUTES" --argjson apiRoutes "$API" --argjson serverActionFiles "$ACTIONS" \
  --argjson hbConfig "$(has .hardbuild.json)" --argjson scorecard "$(has audits/AUDIT-SCORECARD.md)" \
  '{
    framework: (if $next != "" then "nextjs" else "node" end), versions:{next:$next,react:$react,typescript:$ts},
    packageManager:$pm, router:{app:$appRouter,pages:$pagesRouter},
    ui:{tailwind:$tailwind,shadcn:$shadcn},
    supabase:{client:$supabaseJs,ssr:$supabaseSsr,dir:$supabaseDir,migrations:$migrations,edgeFunctions:$edgeFunctions},
    vercel:{vercelJson:$vercelJson,analytics:$vercelAnalytics,speedInsights:$speedInsights},
    services:{stripe:$stripe,sentry:$sentry,posthog:$posthog,resend:$resend,nodemailer:$nodemailer,upstashRatelimit:$upstash},
    i18n:{nextIntl:$nextIntl,i18next:$i18next},
    data:{zod:$zod,prisma:$prisma,drizzle:$drizzle},
    testing:{vitest:$vitest,jest:$jest,playwright:$playwright,testingLibrary:$rtl,testFiles:$testFiles,e2eFiles:$e2eFiles},
    quality:{eslint:$eslint,prettier:$prettier,husky:$husky,tsconfig:$tsconfig,strict:$strict,ci:$ci},
    hygiene:{envExample:$envExample,envLocalPresent:$envLocal,middleware:$middleware,readme:$readme,license:$license},
    size:{tsFiles:$srcFiles,pages:$pages,apiRoutes:$apiRoutes,serverActionFiles:$serverActionFiles},
    hardbuild:{config:$hbConfig,scorecard:$scorecard},
    confidence:"high"
  }'
