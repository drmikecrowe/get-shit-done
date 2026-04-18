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

# Find explicit PLAN.md path in the agent prompt
PLAN_PATH=$(echo "$PROMPT" | grep -oP '\.planning/phases/[^/]+/[^"<\s]+\-PLAN\.md' | head -1 || true)

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
