# Design audit — checks

**Purpose:** Review visual polish and design consistency — one token system, one component set, one typographic scale, and type big and contrasty enough that the owner can read it.
**Scorecard row:** Design · **Report:** `audits/design.md` · **Overlaps:** Accessibility (WCAG contrast math, focus-ring compliance, screen readers), Mobile & Tablet (breakpoints, tap targets), Copy & Content (label wording), Performance (font loading). Reference, don't repeat.

## Inputs to gather first
- Token source: `tailwind.config.{ts,js}` `theme.extend`, `app/globals.css` `:root` / `.dark` CSS variables, `components.json` (shadcn present?).
- Component inventory: `ls components/ui components` and `find components -name '*.tsx' | wc -l`.
- Does dark mode exist? `grep -rn "darkMode\|next-themes\|ThemeProvider" tailwind.config.* app components -l`.
- Browser access for visual checks: `.hardbuild.json → audit.productionUrl` or `next dev`.
- Evidence to attach: the `uniq -c` tables from DSN-01/03/06/12 (paste the top 10 rows), and 1280px screenshots of the three primary screens saved to `audits/evidence/design-*.png`.
- Treat `components/ui/*` (shadcn) as the baseline: modifications there are fine; parallel hand-rolled versions elsewhere are the smell.

## Checks
Format: `ID · weight · check · how to verify (strongest first) · typical failure`

- **DSN-01 · 3 · Colors come from tokens, not hardcoded values.**
  VERIFY: `grep -rnoE "#[0-9a-fA-F]{3,8}\b" app components --include=*.tsx --include=*.css | grep -v globals.css | wc -l` (target 0 outside the token file); `grep -rnoE "(bg|text|border|ring|from|to)-\[#[0-9a-fA-F]+\]" app components --include=*.tsx | wc -l`; `grep -rnoE "rgba?\(" app components --include=*.tsx | wc -l`. READ `globals.css`: semantic tokens (`--primary`, `--muted-foreground`, `--destructive`) must exist and `tailwind.config` must map them.
  FAIL PATTERN: 15+ distinct hex values across components; `bg-[#1e293b]` alongside `bg-slate-800` alongside `bg-background`; brand color defined twice with different values.
- **DSN-02 · 2 · Spacing uses the scale, not arbitrary pixels.**
  VERIFY: `grep -rnoE "\[[0-9]+(px|rem)\]" app components --include=*.tsx | sort | uniq -c | sort -rn | head -20` → each arbitrary value should be rare and justified; `grep -rnoE "(p|m|gap|space-[xy]|w|h)-\[[0-9.]+(px|rem)\]" app components --include=*.tsx | wc -l`. READ three list/card components: consistent `gap-4` / `p-6` rhythm or a mix of `p-5`, `p-[18px]`, `pt-7`?
  FAIL PATTERN: `mt-[13px]`, `gap-[7px]`; sibling cards with different internal padding; `space-y-*` and `gap-*` and margin stacking used interchangeably on the same screen.
- **DSN-03 · 2 · Typography scale is consistent and limited.**
  VERIFY: `grep -rhoE "text-(xs|sm|base|lg|xl|[2-9]xl|\[[^]]+\])" app components --include=*.tsx | sort | uniq -c | sort -rn` → ≤6 sizes in regular use, no arbitrary sizes; `grep -rhoE "font-(thin|light|normal|medium|semibold|bold|black)" app components --include=*.tsx | sort | uniq -c` → ≤3 weights. READ page headers across 4 routes: same h1 class string (or a shared `<PageHeader>`)?
  FAIL PATTERN: `text-[15px]`, `text-[17px]`; h1 is `text-2xl` on one page and `text-3xl font-black` on another; body copy alternates `text-sm` and `text-base` with no rule.
- **DSN-04 · 3 · Large readable type and high contrast (owner requirement).**
  VERIFY: root font size ≥16px: `grep -rnE "font-size|text-\[1[0-5]px\]" app/globals.css` and check `html { font-size }` is not reduced; `grep -rhoE "text-xs" app components --include=*.tsx | wc -l` → `text-xs` (12px) must not carry body copy, labels, or table cells (allow badges/timestamps only). Contrast: `grep -rhoE "text-(gray|slate|zinc|neutral|stone)-(300|400)" app components --include=*.tsx | wc -l` → light-gray text on white is a finding; `text-muted-foreground` must resolve to ≥4.5:1 (read the HSL in `globals.css`; e.g. `215 16% 47%` on white ≈ 4.6:1 passes, `215 16% 57%` fails). In browser: Lighthouse accessibility "contrast" audit or DevTools element contrast badge on body text and placeholder text.
  FAIL PATTERN: table body in `text-xs text-gray-400`; placeholders at `#9ca3af` on white (2.5:1); `html{font-size:14px}` to "fit more in"; min text-size under 14px anywhere in the primary workflow.
- **DSN-05 · 2 · Components are reused, not duplicated.**
  VERIFY: `find components app -name '*.tsx' -exec basename {} \; | sort | uniq -d` → duplicate filenames; `grep -rln "<table" app components --include=*.tsx | wc -l` vs a single `DataTable`; `grep -rhoE "className=\"[^\"]{120,}\"" app components --include=*.tsx | sort | uniq -c | sort -rn | head` → long class strings repeated 3+ times are a component waiting to be extracted. READ `components/ui` is the shadcn set and feature code imports from it rather than hand-rolling `<button className="rounded-md bg-...">`.
  FAIL PATTERN: `Card.tsx`, `InfoCard.tsx`, `StatCard.tsx` with 90% shared markup; raw `<button>` with 40-class strings beside `components/ui/button.tsx`; two Modal implementations.
- **DSN-06 · 1 · One icon set.**
  VERIFY: `grep -rhoE "from ['\"](lucide-react|@heroicons/react[^'\"]*|react-icons[^'\"]*|@radix-ui/react-icons|@tabler/icons-react)['\"]" app components --include=*.tsx | sort | uniq -c` → exactly one family (lucide for shadcn). Inline `<svg` count: `grep -rln "<svg" app components --include=*.tsx | wc -l` (logos excepted). Icon sizes: `grep -rhoE "(h|size)-[3-6]\b" ... ` should cluster on one or two sizes.
  FAIL PATTERN: lucide + heroicons + react-icons/fa in the same nav; icons at `h-3`, `h-4`, `h-5`, `h-6` randomly in one toolbar.
- **DSN-07 · 2 · Button and link hierarchy: one primary action per view.**
  VERIFY: for each primary page, `grep -nE "<Button|variant=" app/<route>/page.tsx components/<feature>/*.tsx` → count buttons with default/primary variant in a single view; must be 1 (2 only for wizard back/next). Links styled as buttons and buttons styled as links must use `buttonVariants`/`variant="link"`, not ad-hoc classes.
  FAIL PATTERN: three solid-primary buttons in one card header; destructive action in primary color; `<a>` with `bg-primary` classes hand-copied from the button.
- **DSN-08 · 2 · Forms: visible labels, inline validation, helper text.**
  VERIFY: `grep -rn "<Input\|<input" app components --include=*.tsx | wc -l` vs `grep -rn "<Label\|<FormLabel\|htmlFor=" app components --include=*.tsx | wc -l` → roughly equal; placeholder-as-label is a finding (`grep -rnE "placeholder=\"[A-Z][a-z]+( [a-z]+)?\"" ... | grep -v Label`). Validation: `react-hook-form` + `zod` with `<FormMessage>` rendered under the field (`grep -rn "FormMessage\|aria-invalid\|errors\." components app --include=*.tsx | wc -l`); `<FormDescription>` used on non-obvious fields.
  FAIL PATTERN: errors shown only as a top-of-form toast; required fields indicated nowhere; label disappears when user types (placeholder-only); numeric fields with no unit or format hint.
- **DSN-09 · 2 · Dark mode is complete (N/A if absent).**
  VERIFY: if `next-themes`/`.dark` exists: `grep -rhoE "\b(bg|text|border)-(white|black|gray-[0-9]+|slate-[0-9]+)\b" app components --include=*.tsx | grep -v "dark:" | wc -l` → raw light-only colors with no `dark:` twin and no semantic token are findings; `grep -rn "dark:" app components --include=*.tsx | wc -l` should be *low* if tokens are used properly (tokens flip automatically). In browser: toggle theme on 3 screens, look for white cards on dark bg, invisible borders, black text in inputs.
  FAIL PATTERN: `bg-white` cards on `.dark` body; `<img>` logos without a dark variant; charts with hardcoded `#000` axis labels; `color-scheme` not set so native selects/scrollbars stay light.
- **DSN-10 · 1 · Loading states are consistent: skeletons for layout, spinners for actions.**
  VERIFY: `find app -name 'loading.tsx' | wc -l` vs number of data-fetching routes; `grep -rn "<Skeleton" app components --include=*.tsx -l | wc -l` vs `grep -rnE "Loader2|animate-spin" app components --include=*.tsx -l | wc -l`. READ: page/section loads → `<Skeleton>` matching the final layout; button submits → inline spinner + `disabled`. Both mixed on one surface is the smell.
  FAIL PATTERN: full-page centered spinner for a dashboard (layout shift on load); skeleton shaped nothing like the content; some tables skeleton, others spinner, others nothing.
- **DSN-11 · 2 · Interactive states exist: hover, focus-visible, active, disabled.**
  VERIFY: `grep -rn "<button\|<a " app components --include=*.tsx | grep -vE "hover:|focus|Button|buttonVariants|Link" | head` → raw interactive elements lacking state classes; shadcn `button.tsx` must keep `focus-visible:ring-2` and `disabled:opacity-50 disabled:pointer-events-none`; `grep -rn "outline-none\|focus:outline-none" app components --include=*.tsx | grep -v "focus-visible"` → focus removed without replacement is a finding (WCAG detail → Accessibility). In browser: Tab through the primary form — ring visible on every control?
  FAIL PATTERN: clickable `<div>` cards with no hover/focus; `outline-none` globally in `globals.css`; disabled buttons that look identical to enabled.
- **DSN-12 · 1 · Visual consistency across the three primary screens.**
  VERIFY: in browser, screenshot `/dashboard`, the core list, and the core create/edit screen at 1280px; compare header height, page-title style, card radius (`grep -rhoE "rounded-(none|sm|md|lg|xl|2xl|3xl|full)" app components --include=*.tsx | sort | uniq -c | sort -rn` → ≤3 radii in use), shadow usage, max-width container (`grep -rhoE "max-w-[a-z0-9]+" app --include=*.tsx | sort | uniq -c`).
  FAIL PATTERN: `rounded-md` cards next to `rounded-2xl` cards; page content at `max-w-5xl` on one route and full-bleed on the next; two different shadow depths on sibling cards.

## Scoring notes
- DSN-04 failing (body text <14px, or primary-workflow text contrast <4.5:1) → CRITICAL for this plugin's owner; grade cap D. DSN-01 failing with 15+ raw hex values is HIGH (a rebrand becomes a rewrite), not CRITICAL.
- DSN-09 is N/A when no dark-mode mechanism exists; say so in one clause. DSN-06 is N/A for icon-free utility apps.
- DSN-08 is N/A only if the app has no forms at all (rare); a login form alone keeps it in scope.
- Grep-based checks (DSN-01/02/03/05/06/07/08/10/11) are READ (85) when you cite counts and `file:line`; browser screenshots upgrade DSN-04/09/11/12 to VERIFIED (100). Counts alone with no file citations are INFERRED (50).
- One root cause, one finding: a missing token system (DSN-01) usually explains DSN-02/03/09 too — file it once under DSN-01 and reference it from the others rather than triple-counting.
- "To raise confidence": `productionUrl` or `next dev` for screenshots and DevTools contrast; Lighthouse accessibility run for DSN-04; the owner's brand/token sheet if one exists outside the repo.
