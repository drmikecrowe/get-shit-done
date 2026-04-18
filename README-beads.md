# GSD + Beads Integration — Graft Reference

This document records exactly how the `beads` branch grafts [Beads](https://github.com/steveyegge/beads)
issue tracking into GSD. Its purpose is to make upstream rebases and conflict resolution fast and unambiguous.

## What Beads Is

Beads (`bd` CLI) is a local-first, git-backed issue tracker. It stores work items in `.beads/` at the project root and injects context into Claude sessions via its own hooks. GSD integrates with it to close the loop between planning artifacts and trackable work items.

## Ownership Split

| Concern | Owner |
|---|---|
| Vision, roadmap, phase planning, verification | GSD |
| Work item lifecycle (status, dependencies, blockers) | Beads |
| Session-to-session memory | Beads |
| Code commits | GSD executor |

**Handoff:** When GSD creates a `PLAN.md` → also create a matching `bd` task and write `bead_id` into the plan frontmatter.

---

## Files Changed vs. `main`

### New files (beads-only)

| File | Role |
|---|---|
| `hooks/gsd-beads-open.sh` | PreToolUse hook: marks a bead `in_progress` before every Agent/Task spawn |
| `hooks/gsd-beads-close.sh` | PostToolUse hook: closes a bead after every Agent/Task return if a matching `SUMMARY.md` exists |
| `docs/Beads-Integration.md` | Legacy summary (predates this file; see below for precise delta) |

### Modified files

#### `bin/install.js`

Two blocks added around line 6353 (after existing hook registrations):

1. **Beads-open hook** — registered as `PreToolUse` with `matcher: 'Agent|Task'`:
   ```
   gsd-beads-open.sh  (timeout: 10s)
   ```

2. **Beads-close hook** — registered as `PostToolUse` with `matcher: 'Agent|Task'`:
   ```
   gsd-beads-close.sh  (timeout: 10s)
   ```

Both hooks are added to:
- The `expectedShHooks` array (checked after copy during install)
- The `gsdHooks` array in `uninstall()` (removed on uninstall)

Hook registration is **idempotent**: skipped if already present. Skipped silently if the `.sh` file doesn't exist at target (e.g., older install).

#### `scripts/build-hooks.js`

Both `.sh` files added to the dist copy list so they ship in the npm package.

#### `agents/gsd-planner.md` — `<step name="create_beads_issues">`

The step was rewritten from "do this if beads is available" (advisory) to **REQUIRED when `.beads/` exists**:

- Guard changed from `# Continue without beads - non-blocking` → hard failure message if `bead_id` not written
- `sed -i "/^---$/a"` replaced with an `awk` script that targets only the **second** `---` line (sed matched both, corrupting frontmatter)
- Success/failure echo added to each bash block so the orchestrator can see what happened

The step creates:
1. A phase `epic` (`bd create ... -t epic --label "phase-N"`) — idempotent, checks first
2. A `task` bead per PLAN.md (`bd create ... --parent $EPIC_ID`) and writes `bead_id: <id>` into plan frontmatter

#### `agents/gsd-executor.md` — `<bead_tracking>`

Restructured from prose + ad-hoc bash to **4 numbered REQUIRED steps**:

```
STEP 1 — Plan start:     read bead_id; HARD GATE if status=blocked; bd update → in_progress
STEP 2 — During:         bd comment add after each task; bd create for discovered work
STEP 3 — When blocked:   bd update → blocked; bd create blocker; bd dep add
STEP 4 — Plan complete:  bd close with reason from SUMMARY
```

Each step has a concrete bash block with `|| true` fallback where tolerated. The old "Non-blocking" label was removed — it was the root cause of agents skipping execution entirely. Now: attempt is **mandatory**, failure is tolerated, skipping is not.

#### `get-shit-done/workflows/execute-phase.md`

**`<step name="check_beads_status" priority="required">`** (was non-required):

- Sets `BEADS_AVAILABLE=true/false` and `BEADS_BLOCKED=true` in bash
- **HARD GATE**: if `BEADS_BLOCKED=true`, workflow STOPS — presents blocked beads to user; does not proceed to wave execution
- User must resolve blockers or type `"override blockers"` to continue

**Before spawning each executor agent** (in wave loop):
- Changed from `if command -v bd` check to `if [ "${BEADS_AVAILABLE:-false}" = "true" ]` (relies on gate variable)
- Reads `bead_id` from PLAN.md frontmatter; updates to `in_progress` with echo confirmation

**After each plan completes** (post spot-checks):
- Closes bead; extracts one-liner from SUMMARY.md for `--reason`

#### `get-shit-done/workflows/execute-plan.md`

Same pattern: `BEADS_AVAILABLE` guard variable, `in_progress` before spawn, `bd close` after commit, `bd sync` at end.

---

## Hook Mechanics

### `gsd-beads-open.sh` (PreToolUse → Agent|Task)

**Trigger:** Fires before every `Agent` or `Task` tool call.

**Guard clauses** (fast-exit, order matters):
1. `.planning/` directory must exist
2. `bd` must be on PATH
3. `.beads/` directory must exist

**Resolution strategy** (finds which PLAN.md to update):
1. Grep prompt for explicit `.planning/phases/.../...-PLAN.md` path
2. Parse `"plan N"` + `"phase M"` text → zero-pad → `find` for matching file

**Action:** Reads `bead_id:` from frontmatter; calls `bd update $BEAD_ID --status in_progress`. Idempotent — skips if already `in_progress` or `closed`.

### `gsd-beads-close.sh` (PostToolUse → Agent|Task)

**Trigger:** Fires after every `Agent` or `Task` tool call returns.

**Guard clauses:** Same as open hook.

**Action:** Iterates `find .planning/phases -name '*-PLAN.md'`. For each:
- Checks if a sibling `*-SUMMARY.md` exists
- Reads `bead_id:` from frontmatter
- Skips if already `closed`
- Calls `bd close $BEAD_ID --reason "Completed: <first ## heading from SUMMARY>"`

---

## PLAN.md Frontmatter Schema

Beads adds one field to every PLAN.md created by `gsd-planner`:

```yaml
---
phase: "01"
plan: "01"
...
bead_id: B-123        # <-- added by create_beads_issues step
---
```

The `awk` insertion targets the **closing** `---` of the YAML block (not the opening one).

---

## Workflow Integration Map

```
/gsd:plan-phase
  └── gsd-planner: create_beads_issues step
        ├── bd create epic (phase-level)
        └── bd create task → write bead_id to PLAN.md

/gsd:execute-phase
  └── check_beads_status (REQUIRED gate)
        ├── BEADS_BLOCKED=true → STOP, show user
        └── BEADS_AVAILABLE=true → proceed
  └── wave loop: for each plan
        ├── before spawn: bd update bead_id → in_progress
        ├── spawn gsd-executor (hook gsd-beads-open fires here)
        │     ├── STEP 1: verify not blocked, update in_progress
        │     ├── STEP 2: comment per task
        │     ├── STEP 3: if blocked → bd update blocked + create blocker dep
        │     └── STEP 4: bd close on plan complete
        └── after return: bd close + bd sync (hook gsd-beads-close fires here)

/gsd:verify-work
  └── (no bead interaction currently — beads already closed by executor)
      NOTE: consider bd comment add $BEAD_ID "Verified: {summary}" post-verification

/gsd:ship
  └── (no bead interaction currently — beads already closed before PR opened)
      KNOWN GAP: bead status "closed" before PR exists misrepresents reality.
      Ideal: bd update $BEAD_ID -s shipped + bd comment "PR: {url}" before final close,
      then close only after PR merged/approved.
```

---

## Known Gaps

1. **Ship/verify lifecycle**: Beads are closed when the executor finishes. The PR and code review haven't happened yet. A `shipped` intermediate state (bead gets PR URL comment, transitions to `closed` only on merge/approval) would more accurately represent reality. This is a future improvement — not currently implemented.

2. **Reviewer integration hook point**: The gap between executor close and PR merge is the natural place to run a cross-AI reviewer. A `shipped` bead state would signal the reviewer to run, and reviewer approval would transition the bead to `closed`.

---

## Configuration (`.planning/config.json`)

```json
{
  "beads_integration": {
    "enabled": true,
    "auto_create_epics": true,
    "auto_create_plan_beads": true,
    "sync_on_session_end": true,
    "track_status": true
  }
}
```

---

## Rebasing onto `main` — What to Watch

When pulling new upstream `main` into this branch:

| File | Risk | Action |
|---|---|---|
| `bin/install.js` | High — large file, active changes upstream | Preserve both beads hook registration blocks (search `gsd-beads`) |
| `agents/gsd-planner.md` | Medium — step content changes upstream | Keep `create_beads_issues` step with awk frontmatter insertion intact |
| `agents/gsd-executor.md` | Medium | Keep the 4-step `bead_tracking` block |
| `get-shit-done/workflows/execute-phase.md` | High — active workflow | Keep `priority="required"` on `check_beads_status`, keep `BEADS_AVAILABLE` variable pattern |
| `get-shit-done/workflows/execute-plan.md` | Medium | Keep `BEADS_AVAILABLE` guard and `bd sync` at end |
| `scripts/build-hooks.js` | Low | Ensure both `.sh` files remain in copy list |
| `hooks/gsd-beads-open.sh` | None (new file) | No conflict expected |
| `hooks/gsd-beads-close.sh` | None (new file) | No conflict expected |

**Key invariant to preserve:** `bead_id` must be written into PLAN.md frontmatter by the planner **before** execute-phase runs. The hook and workflow both read it from there — if the planner step is lost, the whole tracking chain breaks silently.

---

## Prerequisites

```bash
# Install beads
npm install -g @steveyegge/beads   # or whatever the install is
cd <project>
bd init
bd setup claude

# Re-run GSD install to register hooks
gsd install
```

Verify hooks registered:
```bash
cat ~/.claude/settings.json | grep -A5 'gsd-beads'
```

---

## Anti-Patterns

- **Don't** mark beads steps "non-blocking" — agents interpret that as "skip"
- **Don't** use `sed -i "/^---$/a"` to insert into frontmatter — it matches both `---` delimiters; use the `awk` pattern in the planner
- **Don't** override beads' own `SessionStart` hook — coordinate alongside it
- **Don't** skip `bd sync` at session end — JSONL and database diverge
