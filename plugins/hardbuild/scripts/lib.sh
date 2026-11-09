#!/usr/bin/env bash
# HardBuild shared helpers. Sourced by the hook scripts. Bash 3.2+ compatible (macOS default).

hb_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
  elif [ -n "${HB_CWD:-}" ] && [ -d "$HB_CWD" ]; then
    printf '%s' "$HB_CWD"
  else
    pwd
  fi
}

# Per-project state lives outside the repo so nothing leaks into git.
hb_state_dir() {
  local proj; proj="$(hb_project_dir)"
  local base="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/hardbuild}"
  local key
  if command -v md5sum >/dev/null 2>&1; then key="$(printf '%s' "$proj" | md5sum | cut -c1-12)"
  elif command -v md5 >/dev/null 2>&1; then key="$(printf '%s' "$proj" | md5 -q | cut -c1-12)"
  else key="$(printf '%s' "$proj" | cksum | cut -d' ' -f1)"; fi
  local dir="$base/state/$key"
  mkdir -p "$dir" 2>/dev/null
  printf '%s' "$dir"
}

hb_config_file() { printf '%s/.hardbuild.json' "$(hb_project_dir)"; }

# hb_cfg '<jq path>' '<default>'  e.g. hb_cfg '.gates.test' 'true'
hb_cfg() {
  local path="$1" def="$2" f; f="$(hb_config_file)"
  if [ -f "$f" ] && command -v jq >/dev/null 2>&1; then
    # getpath-based so a literal false is honored (jq's // treats false as missing); arrays join with spaces
    local v; v="$(jq -r --arg p "$path" '($p | ltrimstr(".") | split(".")) as $k | getpath($k) | if . == null then empty elif type == "array" then join(" ") else tostring end' "$f" 2>/dev/null)"
    if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  fi
  printf '%s' "$def"
}

hb_pm() {
  local p; p="$(hb_project_dir)"
  if   [ -f "$p/pnpm-lock.yaml" ]; then echo pnpm
  elif [ -f "$p/bun.lockb" ] || [ -f "$p/bun.lock" ]; then echo bun
  elif [ -f "$p/yarn.lock" ]; then echo yarn
  else echo npm; fi
}

# hb_run_script <script-name>  → prints the command to run a package.json script, or nothing
hb_script_cmd() {
  local name="$1" p; p="$(hb_project_dir)"
  [ -f "$p/package.json" ] || return 1
  if jq -e --arg n "$name" '.scripts[$n] // empty' "$p/package.json" >/dev/null 2>&1; then
    case "$(hb_pm)" in
      pnpm) printf 'pnpm run %s' "$name" ;;
      bun)  printf 'bun run %s' "$name" ;;
      yarn) printf 'yarn %s' "$name" ;;
      *)    printf 'npm run %s' "$name" ;;
    esac
    return 0
  fi
  return 1
}

hb_has_dep() {
  local dep="$1" p; p="$(hb_project_dir)"
  [ -f "$p/package.json" ] || return 1
  jq -e --arg d "$dep" '(.dependencies[$d] // .devDependencies[$d]) // empty' "$p/package.json" >/dev/null 2>&1
}

# Portable timeout wrapper: hb_timeout <seconds> <cmd...>
hb_timeout() {
  local secs="$1"; shift
  # Only GNU timeout has this interface; Windows ships its own timeout.exe with different flags.
  if timeout --version 2>/dev/null | grep -q GNU; then timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  else "$@"; fi
}

# Source-file test used by smell + orphan checks
hb_is_source() {
  case "$1" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.sql|*.css|*.scss|*.vue|*.svelte|*.go|*.rs) return 0 ;;
    *) return 1 ;;
  esac
}

hb_is_ignored_path() {
  local f="$1"
  case "$f" in
    */node_modules/*|*/.next/*|*/dist/*|*/build/*|*/coverage/*|*/.git/*|*/audits/*|*/docs/*|*.d.ts|\
    *.test.*|*.spec.*|*/__tests__/*|*/__mocks__/*|*.stories.*|*/e2e/*|*/.hardbuild*) return 0 ;;
  esac
  # user-configured ignore prefixes
  local extra; extra="$(hb_cfg '.ignorePaths' '')"
  local pre
  for pre in $extra; do
    case "$f" in "$(hb_project_dir)/$pre"*|"$pre"*) return 0 ;; esac
  done
  return 1
}

# Hard smells: a line matching any of these means the implementation is not finished.
# `hardbuild-ok` on the same line suppresses it deliberately.
HB_HARD_SMELLS='(^|[^A-Za-z])(TODO|FIXME|HACK)([^A-Za-z]|$)|not implemented|NotImplemented|lorem ipsum|coming soon|// *stub|/\* *stub|throw new Error\(["'"'"']Not implemented|throw new Error\(["'"'"']TODO|return null; *// *(temp|placeholder|stub)|PLACEHOLDER|<placeholder>|your-api-key|YOUR_API_KEY|sk_live_|sk_test_|eyJhbGciOi|hb-placeholder'
# Soft smells: allowed, but Claude is told about them.
HB_SOFT_SMELLS='console\.log\(|@ts-ignore|@ts-expect-error|eslint-disable|as any\b|: any\b|dangerouslySetInnerHTML|localhost:[0-9]+'

hb_scan_smells() {
  # $1 = file path ; prints "line:text" for hard smells
  grep -nE "$HB_HARD_SMELLS" "$1" 2>/dev/null \
    | grep -v 'hardbuild-ok' \
    | grep -viE 'placeholder[=:-]|placeholder"|placeholderText|PlaceholderProps|placeholder\)' \
    | head -20
}

hb_scan_soft() {
  grep -nE "$HB_SOFT_SMELLS" "$1" 2>/dev/null | grep -v 'hardbuild-ok' | head -10
}
