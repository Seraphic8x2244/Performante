# Development Progress

## Current
- Branch: `dev`
- Version: `0.1.0-dev`
- Development/runtime head: `c06d6b71f2296d92a8ecbcba1f13f977841551cc` — initial Performante baseline setup.
- Latest status-only commit before this update: `ae9490519fa334c3127753da33b51e802f173604`.
- Stable baseline: None; `main` currently contains only the repository README.
- Goal: Preserve the accepted 0.1 communications monitor baseline and prepare the agreed Performante 0.2 diagnostic build.
- Current scope boundary: 0.2 adds lightweight frametime/hitch and Lua-memory diagnostics alongside Comms. Full event-storm capture/correlation is deferred.

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
- Prefer cheap always-on measurements. Expensive diagnostic capture must be explicit/temporary rather than permanently active.

### Protocol / Data Model
- 0.1 listens to `CHAT_MSG_ADDON`.
- `arg1` is treated as the communication prefix and is the aggregation key.
- Counts are session/reset scoped only; no SavedVariables yet.
- Sender/channel/payload inspection is intentionally not part of the 0.1 baseline.
- 0.2 frametime monitoring will use per-frame elapsed time and retain only a small recent hitch history.
- 0.2 Lua memory monitoring will use the native 1.12.1 memory information available to Lua and show current/change-since-reset values.

### Active Decisions
- Performante replaces the standalone AddonCommsMonitor concept.
- 0.1 remains the communications counter baseline.
- 0.2 scope is agreed:
  - retain the Comms view;
  - add a Frametime view;
  - show current frame time and worst frame since reset;
  - count hitches above useful thresholds such as 33 ms, 50 ms, 100 ms and 200 ms;
  - retain a short recent hitch log;
  - show Lua memory and change since reset;
  - keep Reset/Pause behaviour simple and global where practical.
- Full event monitoring/correlation is not part of 0.2 and is deferred to a later diagnostic build because broad event capture can itself add measurable overhead.

## Recent Relevant Commits
- Repository `main`: `bbe641fb6237fb740e338af766cca286f5c9e7f7` — initial repository commit.
- `dev`: `c06d6b71f2296d92a8ecbcba1f13f977841551cc` — initial template-aligned Performante runtime baseline.
- `dev`: `ae9490519fa334c3127753da33b51e802f173604` — initial development handoff/status record.
- Current status-only change records the agreed 0.2 scope; no runtime code or addon version changes are included.

## Completed / User-Verified
- The precursor AddonCommsMonitor 0.1.0 was used by the user and its compact live layout was accepted.
- The 0.2 feature plan above has been accepted by the user.
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
- Implement the agreed 0.2 scope on `dev` after the 0.1 renamed baseline is verified.
- Start the 0.2 runtime revision as `0.2.0-dev`.
- Preserve the accepted ACM-derived layout while introducing a clear Comms/Frametime presentation.

## Deferred / Out of Scope
- Full event-storm capture/correlation.
- Any always-on `RegisterAllEvents()` design.
- Sender/channel/payload drill-down.
- SavedVariables or historical sessions.
- Per-addon CPU attribution that the native 1.12.1 client cannot provide directly.

## Release / Promotion Notes
- Main-only or release-only content to preserve: current repository README.
- Known validation debt accepted for release: None.
- External/runtime prerequisites: None beyond a Vanilla WoW 1.12.1-compatible client.

## Exact Next Step
Runtime-test Performante 0.1.0-dev as the renamed ACM baseline; once that passes, implement the agreed 0.2 feature set as 0.2.0-dev without adding full event capture.
