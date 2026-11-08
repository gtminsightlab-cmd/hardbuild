#!/usr/bin/env bash
# Stop / SubagentStop hook: the Definition-of-Done gate.
# Runs only when the project changed since the last passing gate. Checks, in order:
#   typecheck → lint → tests (→ build, opt-in) → thin-build smells on added lines → orphan files never imported.
# Any failure → exit 2 with a precise report; Claude keeps working instead of declaring "done".
# After maxBlocks consecutive failures the gate yields but forces an honest status report instead of a silent pass.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

MODE="full"; [ "${1:-}" = "--subagent" ] && MODE="subagent"
INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

HB_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"; export HB_CWD
PROJ="$(hb_project_dir)"; cd "$PROJ" 2>/dev/null || exit 0
STATE="$(hb_state_dir)"
[ "$(hb_cfg '.enabled' 'true')" = "true" ] || exit 0

# ---- Should we run at all? -------------------------------------------------
IN_GIT=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=1
if [ "$IN_GIT" = 1 ]; then
  FP="$( { git status --porcelain=v1 2>/dev/null; git diff 2>/dev/null; git diff --cached 2>/dev/null; } | { md5sum 2>/dev/null || md5 2>/dev/null || cksum; } | cut -c1-32)"
else
  FP="nogit-$(cat "$STATE/dirty" 2>/dev/null || echo 0)"
fi
# Identical to the last passing gate (of this mode) → nothing new to check.
PASSFILE="$STATE/last-pass-$MODE"
if [ -f "$PASSFILE" ] && [ "$(cat "$PASSFILE")" = "$FP" ]; then exit 0; fi
# A full pass also satisfies the lighter subagent gate.
if [ "$MODE" = "subagent" ] && [ -f "$STATE/last-pass-full" ] && [ "$(cat "$STATE/last-pass-full")" = "$FP" ]; then exit 0; fi
# Nothing edited this session (no marker) and tree clean (or no git) → nothing to gate.
if [ ! -f "$STATE/dirty" ]; then
  if [ "$IN_GIT" = 0 ] || [ -z "$(git status --porcelain 2>/dev/null)" ]; then exit 0; fi
fi
# Not a code project → nothing to gate.
if [ ! -f package.json ] && [ ! -f pyproject.toml ] && [ ! -f go.mod ] && [ ! -f Cargo.toml ]; then exit 0; fi

BUDGET="$(hb_cfg '.budgetSeconds' '240')"
MAXBLOCKS="$(hb_cfg '.maxBlocks' '3')"
FAILS=""
add_fail() { FAILS="${FAILS}
$1"; }

run_gate() {
  # run_gate <label> <command string>
  local label="$1" cmd="$2" out rc detail
  out="$STATE/gate-$label.log"
  CI=true FORCE_COLOR=0 NO_COLOR=1 hb_timeout "$BUDGET" bash -lc "$cmd" >"$out" 2>&1; rc=$?
  if [ $rc -eq 124 ]; then
    add_fail "[$label] TIMED OUT after ${BUDGET}s: $cmd  (raise budgetSeconds in .hardbuild.json or make the step faster)"; return
  fi
  [ $rc -eq 0 ] && return
  detail="$(grep -vE '^\s*$' "$out" | grep -iE 'error|fail|✕|×|expected|received|TS[0-9]{4}|problem' | head -25)"
  [ -z "$detail" ] && detail="$(grep -vE '^\s*$' "$out" | tail -20)"
  add_fail "[$label] FAILED (exit $rc): $cmd
$(printf '%s\n' "$detail" | sed 's/^/    /')
    (full log: $out)"
}

npx_cmd() { case "$(hb_pm)" in pnpm) echo "pnpm exec $1";; bun) echo "bunx $1";; yarn) echo "yarn $1";; *) echo "npx $1";; esac; }

# ---- Gates 1–4: typecheck, lint, tests, build ------------------------------
if [ -f package.json ]; then
  if [ "$(hb_cfg '.gates.typecheck' 'true')" = "true" ]; then
    CMD="$(hb_cfg '.commands.typecheck' '')"
    [ -z "$CMD" ] && CMD="$(hb_script_cmd typecheck || hb_script_cmd type-check || hb_script_cmd tsc || true)"
    [ -z "$CMD" ] && [ -f tsconfig.json ] && CMD="$(npx_cmd 'tsc --noEmit -p tsconfig.json')"
    [ -n "$CMD" ] && run_gate typecheck "$CMD"
  fi
  if [ "$MODE" = "full" ] && [ "$(hb_cfg '.gates.lint' 'true')" = "true" ]; then
    CMD="$(hb_cfg '.commands.lint' '')"; [ -z "$CMD" ] && CMD="$(hb_script_cmd lint || true)"
    [ -n "$CMD" ] && run_gate lint "$CMD"
  fi
  if [ "$MODE" = "full" ] && [ "$(hb_cfg '.gates.test' 'true')" = "true" ]; then
    CMD="$(hb_cfg '.commands.test' '')"
    if [ -z "$CMD" ]; then
      if hb_script_cmd test:unit >/dev/null; then CMD="$(hb_script_cmd test:unit)"
      elif hb_script_cmd test >/dev/null; then
        CMD="$(hb_script_cmd test)"
        # vitest/jest default to watch mode outside CI; force a single run
        hb_has_dep vitest && CMD="$CMD -- --run"
        hb_has_dep jest && CMD="$CMD -- --ci --watchAll=false"
      fi
    fi
    [ -n "$CMD" ] && run_gate test "$CMD"
  fi
  if [ "$MODE" = "full" ] && [ "$(hb_cfg '.gates.build' 'false')" = "true" ]; then
    CMD="$(hb_cfg '.commands.build' '')"; [ -z "$CMD" ] && CMD="$(hb_script_cmd build || true)"
    [ -n "$CMD" ] && run_gate build "$CMD"
  fi
elif [ -f pyproject.toml ]; then
  [ "$(hb_cfg '.gates.typecheck' 'true')" = "true" ] && command -v mypy >/dev/null 2>&1 && run_gate typecheck "mypy ."
  [ "$MODE" = "full" ] && [ "$(hb_cfg '.gates.lint' 'true')" = "true" ] && command -v ruff >/dev/null 2>&1 && run_gate lint "ruff check ."
  [ "$MODE" = "full" ] && [ "$(hb_cfg '.gates.test' 'true')" = "true" ] && command -v pytest >/dev/null 2>&1 && run_gate test "pytest -q -x"
fi

# ---- Gate 5: thin-build smells on ADDED lines only --------------------------
if [ "$IN_GIT" = 1 ] && [ "$(hb_cfg '.gates.smells' 'true')" = "true" ]; then
  SMELLS=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue; [ -f "$f" ] || continue; hb_is_source "$f" || continue; hb_is_ignored_path "$PROJ/$f" && continue
    hits="$(git diff HEAD -U0 -- "$f" 2>/dev/null | grep -E '^\+[^+]' | grep -E "$HB_HARD_SMELLS" | grep -v hardbuild-ok | grep -viE 'placeholder[=:-]|placeholder"' | head -5 | sed "s|^+|    $f: |")"
    [ -n "$hits" ] && SMELLS="$SMELLS
$hits"
  done < <(git diff HEAD --name-only 2>/dev/null)
  while IFS= read -r f; do
    [ -n "$f" ] || continue; [ -f "$f" ] || continue; hb_is_source "$f" || continue; hb_is_ignored_path "$PROJ/$f" && continue
    hits="$(hb_scan_smells "$f" | head -5 | sed "s|^|    $f:|")"
    [ -n "$hits" ] && SMELLS="$SMELLS
$hits"
  done < <(git ls-files --others --exclude-standard 2>/dev/null)
  [ -n "$SMELLS" ] && add_fail "[smells] unfinished code in this change set (TODO/stub/placeholder/secret). Implement it or remove it; if intentional, mark the line // hardbuild-ok:$SMELLS"
fi

# ---- Gate 6: orphan files (created but never wired in) ----------------------
if [ "$MODE" = "full" ] && [ "$IN_GIT" = 1 ] && [ "$(hb_cfg '.gates.orphans' 'true')" = "true" ] && [ -f package.json ]; then
  ORPHANS=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue; [ -f "$f" ] || continue
    case "$f" in *.ts|*.tsx|*.js|*.jsx|*.mjs) ;; *) continue ;; esac
    hb_is_ignored_path "$PROJ/$f" && continue
    base="$(basename "$f")"; name="${base%.*}"; dir="$(basename "$(dirname "$f")")"
    # Framework entry points & config files are wired by convention, not by import
    case "$name" in page|layout|route|loading|error|not-found|template|default|middleware|instrumentation|global-error|sitemap|robots|manifest|opengraph-image|twitter-image|icon|apple-icon|proxy|next-env) continue ;; esac
    case "$f" in *.config.*|.*rc.*|supabase/*|scripts/*|bin/*|*.d.ts|*.setup.*|*.workspace.*) continue ;; esac
    [ "$name" = "index" ] && name="$dir"
    pat="$(printf '%s' "$name" | sed 's/[.[\*^$]/\\&/g')"
    if ! grep -rIlE --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' --include='*.json' --include='*.mdx' \
         --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=dist --exclude-dir=.git --exclude-dir=coverage \
         "(from|import|require|lazy|dynamic)[^;]*['\"/]${pat}(\.[jt]sx?)?['\"]|\"${pat}\"" . 2>/dev/null | grep -v "^\./$f$" | grep -q .; then
      ORPHANS="$ORPHANS
    $f"
    fi
  done < <({ git ls-files --others --exclude-standard; git diff HEAD --name-only --diff-filter=A; } 2>/dev/null | sort -u)
  [ -n "$ORPHANS" ] && add_fail "[orphans] new files that nothing imports — the feature is not wired in. Import/route them, or delete them if unneeded:$ORPHANS"
fi

# ---- Verdict ----------------------------------------------------------------
if [ -z "$FAILS" ]; then
  printf '%s' "$FP" > "$PASSFILE"; rm -f "$STATE/blocks"
  [ "$MODE" = "full" ] && rm -f "$STATE/dirty"
  exit 0
fi

COUNT=$(( $(cat "$STATE/blocks" 2>/dev/null || echo 0) + 1 )); echo "$COUNT" > "$STATE/blocks"
if [ "$COUNT" -gt "$MAXBLOCKS" ]; then
  rm -f "$STATE/blocks"
  MSG="HARDBUILD GATE STILL FAILING after $MAXBLOCKS attempts. You may stop, but you MUST tell the user plainly: the build is NOT done, list exactly which gates fail and why, and do not describe the work as complete or working. Failures:$FAILS"
  jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$m}}'
  exit 0
fi

{
  echo "HARDBUILD GATE FAILED (attempt $COUNT/$MAXBLOCKS, mode=$MODE). The work is NOT done. Fix every item below, re-run the failing command yourself to confirm it passes, then finish:"
  printf '%s\n' "$FAILS"
  echo
  echo "Never weaken tests, add .skip, loosen tsconfig, or disable lint rules to get past this gate. Config lives in .hardbuild.json (enabled, gates, commands, budgetSeconds, maxBlocks, ignorePaths)."
} >&2
exit 2
