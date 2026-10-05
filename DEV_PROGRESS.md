# Development Progress

## Current
- Branch: `dev`
- Version: `0.2.1-dev`
- Development/runtime head: `3727265ccc03a638b47be91bc41223df5ff4a358` — current 0.2.1-dev runtime build.
- Latest tested baseline before 0.2: `bcd1e20784f9c230f5134e2ba589c5037c6d4c45` (`0.1.1-dev`).
- Stable baseline: None; `main` currently contains only the repository README.
- Goal: Extend the now-tested 0.2.1 diagnostics with a compact live frametime graph while preserving the current Comms/Frametime layout.
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
- Counts are session/reset scoped only. `PerformanteDB` persists only whether the monitor window is shown.
- Sender/channel/payload inspection is intentionally not part of the 0.1 baseline.
- 0.2 frametime monitoring uses a dedicated always-active driver frame so measurement continues while the visible window is closed.
- Per-frame `OnUpdate` elapsed time is converted to milliseconds for current/worst frametime and threshold counters.
- Hitch thresholds are cumulative at >33, >50, >100 and >200 ms.
- The recent hitch log keeps four numeric time/value slots for frames >50 ms; it avoids per-hitch table allocation.
- Lua memory uses native `gcinfo()` and is sampled on the 0.5-second refresh cadence, showing current use and change since reset.

### Active Decisions
- Performante replaces the standalone AddonCommsMonitor concept.
- 0.1 remains the communications counter baseline.
- 0.1.1 adds only window open/closed persistence; pause state and counters intentionally remain session-local.
- 0.2 scope is agreed:
  - retain the Comms view;
  - add a Frametime view;
  - show current frame time and worst frame since reset;
  - count hitches above useful thresholds such as 33 ms, 50 ms, 100 ms and 200 ms;
  - retain a short recent hitch log;
  - show Lua memory and change since reset;
  - keep Reset/Pause behaviour simple and global where practical.
- Full event monitoring/correlation is not part of 0.2 and is deferred to a later diagnostic build because broad event capture can itself add measurable overhead.
- Closing the visible monitor must not stop diagnostics; only Pause stops comms, frametime and memory sampling.

## Recent Relevant Commits
- Repository `main`: `bbe641fb6237fb740e338af766cca286f5c9e7f7` — initial repository commit.
- `dev`: `c06d6b71f2296d92a8ecbcba1f13f977841551cc` — initial template-aligned Performante runtime baseline.
- `dev`: `ae9490519fa334c3127753da33b51e802f173604` — initial development handoff/status record.
- `dev`: `e1a68d7d952952e8d7e0d2ee8a2da77bda59198b` — agreed 0.2 scope recorded.
- `dev`: `bcd1e20784f9c230f5134e2ba589c5037c6d4c45` — clean 0.1.1-dev runtime revision adding window visibility persistence.
- Two superseded intermediate visibility-edit commits exist immediately before `bcd1e207`; the clean runtime commit rebuilds from the known-good 0.1 baseline.
- `dev`: `ec71a8bac0eed7bc8c663592cc110cf4ea08f8f8` — recorded the tested 0.1.1 baseline before 0.2 work.
- `dev`: `8d04c2989839b44db7a98f908ddfb801196bbd13` — initial 0.2.0-dev implementation; superseded before runtime testing.
- `dev`: `3727265ccc03a638b47be91bc41223df5ff4a358` — 0.2.1-dev; fixes Vanilla-safe backdrop escaping and removes per-hitch table allocation. User-tested and accepted.

## Completed / User-Verified
- The precursor AddonCommsMonitor 0.1.0 was used by the user and its compact live layout was accepted.
- The 0.2 feature plan above has been accepted by the user.
- Performante 0.1.0-dev at `c06d6b71f2296d92a8ecbcba1f13f977841551cc` was user-tested after the rename/repackage and reported working.
- Performante 0.1.1-dev at `bcd1e20784f9c230f5134e2ba589c5037c6d4c45` was user-tested: visibility persistence worked across reload and the existing monitor remained functional.
- Performante 0.2.1-dev at `3727265ccc03a638b47be91bc41223df5ff4a358` was user-tested: Comms, Frametime, hitch counters/history, memory display, Reset/Pause, hidden-window collection and open/closed persistence all appeared to work.

## Implemented / Awaiting Runtime Test
- None for the tested 0.2.1 baseline.
- Next runtime delta: a dedicated Graph tab with an approximately 8-second rolling frametime visualization, sampled at 10 Hz using the worst frame in each 100 ms bucket.

## Static / Automated Checks
- Manual compatibility review against the VanillaTemplate 1.12.1/Lua 5.0.3 rules.
- Verified current source uses 82 total `local` tokens even when counting function-body locals, comfortably below the 200-local compiler ceiling for the top-level chunk.
- Verified addon texture paths contain Lua-safe doubled backslashes in source.
- Verified 0.2 uses a separate always-active driver frame, native `gcinfo()`, all four agreed hitch thresholds, fixed-slot hitch history, and preserved visibility SavedVariable behavior.
- Canonical `tools/lua50/check_lua50.sh` compiler check not run in this chat because the GitHub connector does not provide the private template checkout as an executable filesystem tree.

## Current Issues
- None known in the tested 0.1.1-dev baseline.
- No known runtime issues in the tested 0.2.1-dev baseline.

## Testing

### Last Runtime Test
- Version/commit: `0.2.1-dev` / `3727265ccc03a638b47be91bc41223df5ff4a358`.
- Passed: Comms and Frametime tabs, current/worst frametime, hitch counters/history, Lua memory display, Reset/Pause, hidden-window diagnostics and open/closed persistence all appeared to work.
- Failed: None reported.
- Not tested: Upcoming Graph-tab runtime delta.

### Next Runtime Test
- Test the forthcoming Graph tab for layout, scrolling behavior, hitch visibility, Reset/Pause interaction, hidden-window collection and regression of the tested Comms/Frametime views.

## Planned / Next Work
- Add a third Graph tab without enlarging the existing window.
- Keep roughly 80 fixed numeric samples at 10 Hz (~8 seconds).
- Store the worst frame seen in each 100 ms bucket so brief hitches remain visible.
- Pre-create/reuse graph textures; do not allocate UI objects while sampling.
- Keep event correlation as a separate later scope.

## Deferred / Out of Scope
- Full event-storm capture/correlation.
- Any always-on `RegisterAllEvents()` design.
- Sender/channel/payload drill-down.
- Persisted counters or historical sessions.
- Per-addon CPU attribution that the native 1.12.1 client cannot provide directly.

## Release / Promotion Notes
- Main-only or release-only content to preserve: current repository README.
- Known validation debt accepted for release: None.
- External/runtime prerequisites: None beyond a Vanilla WoW 1.12.1-compatible client.

## Exact Next Step
Implement the Graph-tab runtime delta on top of tested `0.2.1-dev`, keeping the existing 330x286 window footprint and event capture deferred.
