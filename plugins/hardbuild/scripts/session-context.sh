#!/usr/bin/env bash
# SessionStart hook: puts the HardBuild working rules + current scorecard status into context.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
HB_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"; export HB_CWD
P="$(hb_project_dir)"

RULES="$(cat "$HERE/../templates/RULES.md" 2>/dev/null | head -c 6000)"

STATUS=""
if [ -f "$P/audits/AUDIT-SCORECARD.md" ]; then
  STATUS="Current audit scorecard (audits/AUDIT-SCORECARD.md):
$(grep -E '^\|' "$P/audits/AUDIT-SCORECARD.md" | head -30)"
else
  STATUS="No audit scorecard yet in this project. Run /hardbuild:audit all to create audits/AUDIT-SCORECARD.md."
fi

GATES="HardBuild gates active this session: typecheck, lint, tests, thin-build smells, orphan files (configure in .hardbuild.json; enabled=$(hb_cfg '.enabled' 'true'))."
[ -f "$P/.hardbuild.json" ] || GATES="$GATES No .hardbuild.json found — defaults apply. Create one from the plugin's templates/.hardbuild.json to tune commands and budgets."

CTX="$RULES

$GATES

$STATUS"
jq -cn --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
