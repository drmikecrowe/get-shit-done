#!/usr/bin/env bash
# gsd-hook-version: {{GSD_VERSION}}
# gsd-beads-open.sh — PreToolUse hook on Agent|Task
# Before every subagent spawn, mark the target plan's bead as in_progress.
# No-op outside GSD execution contexts (guard clauses exit fast).

set -euo pipefail

# Guard clauses — exit fast when not in a GSD execution context
[[ -d .planning ]] || exit 0
command -v bd &>/dev/null || exit 0
[[ -d .beads ]] || exit 0

# Read the tool input JSON from stdin
INPUT=$(cat)

# Extract the agent prompt using Node (handles escaping safely, no jq needed for this)
PROMPT=$(echo "$INPUT" | node -e "
  let d = '';
  process.stdin.on('data', c => d += c);
  process.stdin.on('end', () => {
    try {
      const obj = JSON.parse(d);
      process.stdout.write(obj.tool_input?.prompt || '');
    } catch { process.stdout.write(''); }
  });
" 2>/dev/null || true)

[[ -n "$PROMPT" ]] || exit 0

# Strategy 1: find an explicit PLAN.md file path in the prompt
PLAN_PATH=$(echo "$PROMPT" | grep -oP '\.planning/phases/[^/]+/[^"<\s]+\-PLAN\.md' | head -1 || true)

# Strategy 2: parse "plan NN of phase MM" or "plan NN phase MM" text
if [[ -z "$PLAN_PATH" ]] && [[ -d .planning/phases ]]; then
    PHASE_NUM=$(echo "$PROMPT" | grep -oP '(?<=phase )\d+' | head -1 || true)
    PLAN_NUM=$(echo "$PROMPT"  | grep -oP '(?<=plan )\d+'  | head -1 || true)

    if [[ -n "$PHASE_NUM" && -n "$PLAN_NUM" ]]; then
        # Zero-pad single digits (01, 02, ...)
        PHASE_PAD=$(printf '%02d' "$PHASE_NUM")
        PLAN_PAD=$(printf '%02d' "$PLAN_NUM")
        PLAN_PATH=$(find .planning/phases -name "${PHASE_PAD}-${PLAN_PAD}-PLAN.md" 2>/dev/null | head -1 || true)
        [[ -n "$PLAN_PATH" ]] || \
            PLAN_PATH=$(find .planning/phases -name "*PLAN.md" 2>/dev/null \
                | grep "/${PHASE_PAD}-${PLAN_PAD}-" | head -1 || true)
    fi
fi

[[ -n "$PLAN_PATH" && -f "$PLAN_PATH" ]] || exit 0

# Read bead_id from plan frontmatter
BEAD_ID=$(grep -Po '^bead_id: \K.*' "$PLAN_PATH" 2>/dev/null || true)
[[ -n "$BEAD_ID" ]] || exit 0

# Skip if already in_progress or closed (idempotent)
STATUS=$(bd show "$BEAD_ID" --json 2>/dev/null | jq -r '.status // "unknown"' || echo "unknown")
if [[ "$STATUS" == "in_progress" || "$STATUS" == "closed" ]]; then
    exit 0
fi

# Mark in_progress
bd update "$BEAD_ID" --status in_progress 2>/dev/null \
    && echo "gsd-beads: ${BEAD_ID} → in_progress ($(basename "$PLAN_PATH"))" \
    || echo "gsd-beads: WARNING — failed to update ${BEAD_ID}"

exit 0
