#!/usr/bin/env bash
# gsd-hook-version: {{GSD_VERSION}}
# gsd-beads-close.sh — PostToolUse hook on Agent|Task
# After every subagent return, close beads for plans that now have a SUMMARY.md.
# No-op outside GSD execution contexts (guard clauses exit fast).

set -euo pipefail

# Guard clauses — exit fast when not in a GSD execution context
[[ -d .planning ]] || exit 0
command -v bd &>/dev/null || exit 0
[[ -d .beads ]] || exit 0
[[ -d .planning/phases ]] || exit 0

# For each PLAN.md, check if SUMMARY.md now exists and bead is still open
while IFS= read -r -d '' PLAN; do
    PHASE_DIR=$(dirname "$PLAN")
    BASENAME=$(basename "$PLAN" -PLAN.md)   # e.g. 01-01
    SUMMARY="${PHASE_DIR}/${BASENAME}-SUMMARY.md"

    # Only process plans that have a completed SUMMARY
    [[ -f "$SUMMARY" ]] || continue

    # Read bead_id from frontmatter
    BEAD_ID=$(grep -Po '^bead_id: \K.*' "$PLAN" 2>/dev/null || true)
    [[ -n "$BEAD_ID" ]] || continue

    # Skip if already closed
    STATUS=$(bd show "$BEAD_ID" --json 2>/dev/null | jq -r '.status // "unknown"' || echo "unknown")
    [[ "$STATUS" != "closed" ]] || continue

    # Extract one-liner from SUMMARY for closure reason
    ONELINER=$(grep "^## " "$SUMMARY" 2>/dev/null | head -1 | sed 's/^## //' || echo "plan ${BASENAME} completed")

    # Close the bead
    bd close "$BEAD_ID" --reason "Completed: ${ONELINER}" 2>/dev/null \
        && echo "gsd-beads: closed ${BEAD_ID} (${BASENAME})" \
        || echo "gsd-beads: WARNING — failed to close ${BEAD_ID} (${BASENAME})"

done < <(find .planning/phases -name '*-PLAN.md' -print0 2>/dev/null)

exit 0
