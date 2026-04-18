# GSD + Beads Integration Summary

## Overview

This integration makes GSD (Get Shit Done) automatically create and track beads issues during the planning and execution workflow, while respecting Beads' hook-based context injection mechanism.

## Files Modified

### 1. `agents/gsd-planner.md`
- Added `<step name="create_beads_issues">` to create corresponding beads issues after plan creation
- Added `bead_id` field to PLAN.md frontmatter schema
- Updated `PLAN.md Structure` example to include bead_id
- Added Beads issues creation to "Planning Complete" return format
- Updated success criteria to include beads verification

### 2. `agents/gsd-executor.md`
- Added `<bead_tracking>` section with BEAD TRACKING PROTOCOL
- Covers: plan start, during execution, when blocked, task completion, plan completion
- Updated success criteria to include bead status updates

### 3. `commands/gsd/new-project.md` (via `get-shit-done/workflows/new-project.md`)
- Added Step 8.5: "Initialize Beads Tracking"
- Initializes beads if not present
- Creates epic for each phase in the roadmap
- Updated success criteria and output sections

### 4. `get-shit-done/workflows/execute-phase.md`
- Added `<step name="check_beads_status">` to check bead status before execution
- Added bead status update to "in_progress" before spawning executor agents
- Added bead status update to "closed" after plan completion

### 5. `get-shit-done/workflows/execute-plan.md`
- Added `<step name="check_bead_status">` to check bead status before plan execution
- Added bead closing to `git_commit_metadata` step
- Added `bd sync` call to sync beads database

### 6. `get-shit-done/templates/config.json`
- Added `beads_integration` section with settings:
  - `enabled`: Enable/disable beads integration
  - `auto_create_epics`: Auto-create phase epics
  - `auto_create_plan_beads`: Auto-create beads for plans
  - `sync_on_session_end`: Sync beads database on session end
  - `track_status`: Track bead status during execution

### 7. `.claude/hooks/SessionStart.sh` (new file)
- Shows GSD phase information alongside beads context
- Displays ready work items for current phase
- Coordinates with beads' own hooks

### 8. `.claude/hooks/PreCompact.sh` (new file)
- Syncs beads database before context compaction
- Adds session end comments to current bead

## Integration Architecture

### Layered Responsibility
- **GSD** owns: Vision, requirements, domain research, phase planning, verification
- **Beads** owns: Work item tracking, dependencies, status, session-to-session memory
- **Handoff point**: When GSD creates PLAN.md → also create matching `bd` issues

### Key Integration Points

1. **Project Initialization** (`/gsd:new-project`):
   - Initializes beads if not present
   - Creates epic for each phase in ROADMAP.md

2. **Phase Planning** (`/gsd:plan-phase`):
   - Creates beads issues for each plan
   - Records bead_id in PLAN.md frontmatter
   - Creates child beads for tasks (optional)

3. **Execution** (`/gsd:execute-phase`):
   - Checks bead status before execution
   - Updates bead to in_progress at start
   - Adds comments for technical notes
   - Closes bead with reason on completion
   - Syncs beads database

4. **Session Hooks**:
   - SessionStart: Shows GSD + Beads combined status
   - PreCompact: Syncs beads database, adds session summary

## Usage

### Initial Setup
```bash
# Initialize a new GSD project (automatically sets up beads)
/gsd:new-project

# Or manually initialize beads in existing project
bd init
bd setup claude
```

### During Planning
```bash
# Plan a phase - automatically creates beads issues
/gsd:plan-phase 1

# Check ready work queue
bd ready
```

### During Execution
```bash
# Execute phase - automatically updates bead status
/gsd:execute-phase 1

# Check bead status
bd show <bead-id>
```

## Configuration

Edit `.planning/config.json`:

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

## Key Principles

1. **Don't replace beads hooks**: GSD coordinates WITH beads, not override it
2. **bd CLI over MCP**: Use direct `bd` commands for performance
3. **Beads is source of truth for status**: Trust bead status over PLAN.md
4. **GSD owns planning, Beads owns memory**: Clear separation of concerns
5. **Always run bd sync**: Ensure JSONL and database stay synchronized

## Anti-Patterns to Avoid

❌ Don't create a separate MCP server for GSD-beads communication
❌ Don't try to replace PLAN.md with beads issues
❌ Don't override beads' SessionStart hooks
❌ Don't use TodoWrite when beads is available
❌ Don't create beads issues manually when GSD can automate it

## Testing Checklist

- [ ] Fresh project test: Run `/gsd:new-project` and verify beads epics are created
- [ ] Planning test: Run `/gsd:plan-phase 1` and verify beads issues are created
- [ ] Execution test: Run `/gsd:execute-phase 1` and verify bead status updates
- [ ] Session boundary test: Close session, reopen, verify beads context is available
- [ ] Blocking test: Mark a task as blocked, verify bead dependencies are created

## References

- Beads: https://github.com/steveyegge/beads
- Beads workflow docs: `bd prime` output after `bd setup claude`
- GSD architecture: `.planning/` structure and agent system
