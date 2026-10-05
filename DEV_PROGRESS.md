# Development Progress

## Current
- Branch: `dev`
- Version: `0.1.0-dev`
- Development head: `c06d6b71f2296d92a8ecbcba1f13f977841551cc` — initial Performante baseline setup commit.
- Stable baseline: None; `main` currently contains only the repository README.
- Goal: Establish the Performante 0.1 development baseline from the accepted AddonCommsMonitor layout and communication counter.
- Current scope boundary: Repository/template adoption plus the 0.1 communication monitor only. Do not implement 0.2 performance diagnostics until scope is discussed and agreed.

## Current Design / Development Contract

### Architecture / Ownership
- Native World of Warcraft 1.12.1 / Lua 5.0.3 addon.
- Keep the addon small: one main runtime file, `Performante.lua`, plus `locales/enUS.lua`.
- `.toc` metadata is the version source of truth.
- User-facing strings live in the locale file.
- The compact draggable AddonCommsMonitor window is the accepted visual/layout baseline.

### Invariants
- Diagnostic features must keep their own runtime overhead low enough not to meaningfully distort the performance being measured.
- Do not infer an addon folder directly from a communication prefix unless the mapping is established.
- Preserve native 1.12.1 compatibility; do not use later WoW APIs or later Lua syntax.

### Protocol / Data Model
- 0.1 listens to `CHAT_MSG_ADDON`.
- `arg1` is treated as the communication prefix and is the aggregation key.
- Counts are session/reset scoped only; no SavedVariables yet.
- Sender/channel/payload inspection is intentionally not part of the 0.1 baseline.

### Active Decisions
- Performante replaces the standalone AddonCommsMonitor concept.
- 0.1 remains the communications counter baseline.
- 0.2 scope is intentionally undecided pending discussion.

## Recent Relevant Commits
- Repository `main`: `bbe641fb6237fb740e338af766cca286f5c9e7f7` — initial repository commit.
- `dev`: `c06d6b71f2296d92a8ecbcba1f13f977841551cc` — initial template-aligned Performante baseline setup commit.

## Completed / User-Verified
- The precursor AddonCommsMonitor 0.1.0 was used by the user and its compact live layout was accepted.
- This does not count as a runtime test of the renamed/repackaged Performante build.

## Implemented / Awaiting Runtime Test
- Performante 0.1.0-dev addon skeleton and localization.
- ACM-derived live addon-message prefix counter.
- Draggable live window, sorted counts, total count, Reset, Pause/Resume, close button, and slash toggles.

## Static / Automated Checks
- Manual compatibility review against the VanillaTemplate 1.12.1/Lua 5.0.3 rules.
- Canonical `tools/lua50/check_lua50.sh` compiler check not run in this chat because the GitHub connector does not provide the private template checkout as an executable filesystem tree.

## Current Issues
- None known.
- Performante 0.1.0-dev has not yet been loaded in the target client.

## Testing

### Last Runtime Test
- Version/commit: None for Performante.
- Passed: None.
- Failed: None.
- Not tested: Initial load, UI controls, addon-message counting, sorting, slash commands.

### Next Runtime Test
1. Load Performante 0.1.0-dev in the 1.12.1 client and confirm there are no Lua errors.
2. Generate known addon communication and confirm prefixes/counts rise correctly.
3. Verify Reset, Pause/Resume, dragging, close, `/perf`, and `/performante`.

## Planned / Next Work
- Discuss and agree the 0.2 diagnostic scope before implementation.

## Deferred / Out of Scope
- Frametime/hitch measurement.
- Lua memory monitoring.
- Event-storm capture/correlation.
- Sender/channel/payload drill-down.
- SavedVariables or historical sessions.
- Any always-on `RegisterAllEvents()` design.

## Release / Promotion Notes
- Main-only or release-only content to preserve: current repository README.
- Known validation debt accepted for release: None.
- External/runtime prerequisites: None beyond a Vanilla WoW 1.12.1-compatible client.

## Exact Next Step
Discuss the 0.2 feature set and measurement design before making any further runtime changes.
