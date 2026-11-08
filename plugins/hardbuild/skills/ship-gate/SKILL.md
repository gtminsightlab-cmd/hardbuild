---
name: ship-gate
description: Definition-of-Done check before declaring any task complete or deploying. Runs typecheck, lint, tests, build (optional), scans the change set for stubs/placeholders/orphan files, checks env/migrations/wiring, and has an independent verifier reproduce the completion claim. Use before saying "done", before a PR, before `vercel --prod`, or when asked "is this ready?".
argument-hint: "[--build] [--deploy] [feature description]"
allowed-tools: Read Grep Glob Bash Agent
---

# /hardbuild:ship-gate — prove it's done before you say it's done

The user is tired of "done" that isn't. This skill turns the Definition of Done into an executable checklist, runs it, and produces an honest verdict. **If any item fails, the verdict is NOT DONE** — no softening.

## 1. Establish the change set
- `git status --porcelain` and `git diff --stat HEAD` (or against the base branch if on a feature branch: `git diff --stat origin/main...HEAD`). List touched files. If nothing changed, say so and stop.
- From `$ARGUMENTS` (or the conversation), state in one sentence what feature/fix this change set claims to deliver.

## 2. Run the mechanical gates (quote each command and its result)
Detect the package manager from the lockfile. Use `.hardbuild.json` → `commands.*` if set, otherwise the package.json scripts.
1. **Typecheck** — `typecheck`/`type-check` script, else `tsc --noEmit`.
2. **Lint** — `lint` script.
3. **Tests** — `test:unit` or `test` (force single run: `-- --run` for vitest, `-- --ci --watchAll=false` for jest). Note which tests cover the touched files; if none do, that is a FAIL for "tested", not a pass.
4. **Build** — only with `--build` or `--deploy`: `build` script (`next build`). Watch for "Dynamic server usage", missing env, and type errors that only surface at build.
5. **Thin-build scan** of added lines: `git diff HEAD -U0 | grep -E '^\+' | grep -nE 'TODO|FIXME|HACK|not implemented|lorem ipsum|coming soon|// *stub|PLACEHOLDER'` plus untracked files. Any hit without `hardbuild-ok` = FAIL.
6. **Orphan scan**: every new `.ts/.tsx/.js/.jsx` file that is not a Next.js convention file (page/layout/route/loading/error/middleware…) must be imported somewhere (`grep -rE "from ['\"].*<name>['\"]"`). Unimported = FAIL ("built but not wired in").
7. **Wiring checks**: new env vars in code (`process.env.X`) appear in `.env.example`; new migrations under `supabase/migrations` have been applied (`supabase migration list` / Supabase MCP) or the apply command is stated; new routes are linked from navigation or documented; new server actions/API routes validate input and check auth (open them and cite the lines).
8. **Mobile sanity** (if UI changed): confirm the new screen has loading/empty/error states and no fixed widths > 360px; if Playwright is installed, run the relevant spec at a 375px viewport.

## 3. Independent verification
Spawn `hardbuild:verifier` with the completion claim from step 1 and the list of touched files. Include its table verbatim in the output. If it says "Not done", the verdict is NOT DONE.

## 4. Verdict (this exact shape)
```
SHIP GATE: DONE | NOT DONE
Claim: <one sentence>
Gates: typecheck ✔/✘ · lint ✔/✘ · tests ✔/✘ (<n> covering touched files) · build ✔/✘/skipped · smells ✔/✘ · orphans ✔/✘ · wiring ✔/✘ · mobile ✔/✘/n/a
Verifier: CONFIRMED | NOT DONE — <one line>
Remaining work (if any):
  1. ...
Proof: <the exact commands run and their one-line results>
```
With `--deploy` and a DONE verdict, finish with the deploy command to run and the post-deploy smoke checks (production URL 200s, auth flow, one write path), but do not deploy yourself unless the user asked for that in this conversation.

## Rules
- Never make tests pass by weakening them. Never skip a gate silently — if a gate cannot run, show it as ✘ with the reason.
- A gate that "would probably pass" is ✘. Only what ran counts.
- Keep the verdict block exactly in the shape above so it can be scanned at a glance.
