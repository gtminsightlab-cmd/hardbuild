#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit|NotebookEdit).
# 1) Marks the project dirty so the Stop gate knows to run.
# 2) Scans the file just written for "thin build" smells (TODO, stubs, placeholders, pasted secrets).
#    Hard smells → exit 2: Claude gets the list and must finish the implementation before moving on.
#    Soft smells → additionalContext warning, no block.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

HB_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"; export HB_CWD
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"

STATE="$(hb_state_dir)"
date +%s > "$STATE/dirty"

[ -n "$FILE" ] || exit 0
[ -f "$FILE" ] || exit 0
[ "$(hb_cfg '.gates.smells' 'true')" = "true" ] || exit 0
hb_is_source "$FILE" || exit 0
hb_is_ignored_path "$FILE" && exit 0

HARD="$(hb_scan_smells "$FILE")"
SOFT="$(hb_scan_soft "$FILE")"
REL="${FILE#"$(hb_project_dir)"/}"

if [ -n "$HARD" ]; then
  {
    echo "HARDBUILD: unfinished code left in $REL (via $TOOL). Finish it now — do not move on to the next step with stubs in place:"
    printf '%s\n' "$HARD" | sed 's/^/  /'
    echo "Rules: no TODO/FIXME/stub/placeholder/'not implemented' in shipped source; no secrets in code. If a line is intentional, append  // hardbuild-ok  and say why."
  } >&2
  exit 2
fi

if [ -n "$SOFT" ]; then
  MSG="HardBuild note for $REL — allowed but review before finishing: $(printf '%s' "$SOFT" | tr '\n' ' ' | cut -c1-600)"
  jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
fi
exit 0
