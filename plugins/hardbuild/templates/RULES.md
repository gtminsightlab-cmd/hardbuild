# HardBuild working rules (Definition of Done)

These rules are in force for all code work in this project. They exist because thin builds — stubs, half-wired features, "I'll finish this later" — are failures, not progress.

## 1. Done means verified, not written
- A task is done only when: it typechecks, lints, its tests pass, the feature is reachable from the UI or API it belongs to, and you have personally run the proving command and read the output.
- Never say "done", "complete", "working", or "should work" without quoting the command you ran and its result. If you could not run it, say exactly that.
- The Stop gate (typecheck → lint → test → smells → orphans) will block you if these are false. Do not work around it: no `.skip`, no `@ts-ignore`, no loosened tsconfig, no disabled lint rules, no deleted tests.

## 2. No placeholders in shipped code
- Zero TODO / FIXME / HACK / "not implemented" / "coming soon" / lorem ipsum / stub returns / mock data in non-test source.
- If something must be deferred, implement the honest version: an explicit error with a clear message, a feature flag, or a tracked issue — and tell the user. Mark a deliberate exception with `// hardbuild-ok <reason>`.
- Never paste secrets or keys into source. Use env vars and update `.env.example`.

## 3. Every file is wired in
- A new component, hook, util, or module must be imported somewhere real before you finish. A new route must be linked or documented. A new migration must be applied (or the apply command given). A new env var must be in `.env.example` and the deploy config.
- When you create N pieces of a feature, finish all N. Do not move to the next step with a piece half-built. If the task is too large for one pass, say so and list what remains — do not pretend.

## 4. Build in full slices, then prove them
- Prefer one complete vertical slice (schema → query → API/action → UI → test) over several partial layers.
- After each slice: run typecheck + the relevant test. Fix immediately. Then proceed.
- When you change a signature or schema, grep for every caller and update them all in the same pass.

## 5. Next.js + Supabase + Vercel specifics
- Every table has RLS enabled with explicit policies; the service-role key is server-only; the anon key only reaches the client via `NEXT_PUBLIC_`.
- Server Actions and route handlers validate input (zod) and check auth before touching data.
- No `any` escapes at data boundaries: generate Supabase types and use them.
- Loading, error, and empty states exist for every data-driven view. Mobile (375px) is checked for every new screen.
- Env vars referenced in code exist in `.env.example` and are documented for Vercel.

## 6. Audits are evidence-based
- An audit finding without `file:line` (or URL + selector) or a command result is not a finding. Verify before you report.
- Scores carry a confidence. Below 90% confidence, say what would raise it. Never inflate a score to look finished.

## 7. Honest reporting beats a pretty summary
- End every work session with: what was built, how it was proven (commands + results), what is NOT done, and known risks. If the gate yielded after repeated failures, lead with that.
