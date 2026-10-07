# Development Progress

## Current
- Branch: `dev`
- Version: `0.2.3-dev`
- Development/runtime head: `b051fa642c35a49e809600903b96d0e4984d5b45` — current 0.2.3-dev graph runtime build.
- Latest tested baseline: `3727265ccc03a638b47be91bc41223df5ff4a358` (`0.2.1-dev`).
- Stable baseline: None; `main` currently contains only the repository README.
- Goal: Preserve the now-user-verified 0.2.3 Comms / Frametime / Graph diagnostic build and decide the next scoped feature.
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
- Lua memory uses native `gcinfo()` and is sampled on the 0.5-second refresh cadence, showing current use and change since reset.
- 0.2.3 replaces the textual recent-hitch timestamp list with a dedicated Graph tab.
- Graph history uses 80 fixed numeric samples at 10 Hz (~8 seconds), stored in a preallocated ring buffer.
- Each 100 ms graph bucket records the worst frame seen in that bucket; brief hitches therefore survive downsampling.
- Graph rendering uses 80 pre-created texture bars, 33/50/100/200 ms guide lines and a fixed 200 ms visual ceiling. Numeric Worst remains uncapped.
- Graph repaint is limited to 5 Hz and only occurs while the Graph tab is visible and monitoring is not paused.

### Active Decisions
- Performante replaces the standalone AddonCommsMonitor concept.
- 0.1 remains the communications counter baseline.
- 0.1.1 adds only window open/closed persistence; pause state and counters intentionally remain session-local.
- 0.2 scope is agreed:
  - retain the Comms view;
  - add a Frametime view;
  - show current frame time and worst frame since reset;
  - count hitches above useful thresholds such as 33 ms, 50 ms, 100 ms and 200 ms;
  - provide a compact rolling frametime graph instead of client-uptime hitch timestamps;
  - show Lua memory and change since reset;
  - keep Reset/Pause behaviour simple and global where practical.
- Full event monitoring/correlation is not part of 0.2 and is deferred to a later diagnostic build because broad event capture can itself add measurable overhead.
- Closing the visible monitor must not stop diagnostics; only Pause stops comms, frametime, graph sampling and memory sampling.
- Pause also suppresses periodic graph/UI redraw work; button-driven state changes still refresh immediately.

## Recent Relevant Commits
- Repository `main`: `bbe641fb6237fb740e338af766cca286f5c9e7f7` — initial repository commit.
- `dev`: `c06d6b71f2296d92a8ecbcba1f13f977841551cc` — initial template-aligned Performante runtime baseline.
- `dev`: `ae9490519fa334c3127753da33b51e802f173604` — initial development handoff/status record.
- `dev`: `e1a68d7d952952e8d7e0d2ee8a2da77bda59198b` — agreed 0.2 scope recorded.
- `dev`: `bcd1e20784f9c230f5134e2ba589c5037c6d4c45` — clean 0.1.1-dev runtime revision adding window visibility persistence.
- Two superseded intermediate visibility-edit commits exist immediately before `bcd1e207`; the clean runtime commit rebuilds from the known-good 0.1 baseline.
- `dev`: `ec71a8bac0eed7bc8c663592cc110cf4ea08f8f8` — recorded the tested 0.1.1 baseline before 0.2 work.
- `dev`: `8d04c2989839b44db7a98f908ddfb801196bbd13` — initial 0.2.0-dev implementation; superseded before runtime testing.
- `dev`: `3727265ccc03a638b47be91bc41223df5ff4a358` — 0.2.1-dev; user-tested and accepted.
- `dev`: `a4cef40e43df3cf2950123125a33d39b278406c9` — 0.2.2-dev initial Graph-tab implementation; superseded before runtime testing.
- `dev`: `b051fa642c35a49e809600903b96d0e4984d5b45` — 0.2.3-dev; current Graph-tab build, additionally suppressing periodic redraw work while paused.

## Completed / User-Verified
- The precursor AddonCommsMonitor 0.1.0 was used by the user and its compact live layout was accepted.
- The 0.2 feature plan above has been accepted by the user.
- Performante 0.1.0-dev at `c06d6b71f2296d92a8ecbcba1f13f977841551cc` was user-tested after the rename/repackage and reported working.
- Performante 0.1.1-dev at `bcd1e20784f9c230f5134e2ba589c5037c6d4c45` was user-tested: visibility persistence worked across reload and the existing monitor remained functional.
- Performante 0.2.1-dev at `3727265ccc03a638b47be91bc41223df5ff4a358` was user-tested: Comms, Frametime, hitch counters/history, memory display, Reset/Pause, hidden-window collection and open/closed persistence all appeared to work.

## Implemented / Awaiting Runtime Test
- Added a third Graph tab without increasing the 330x286 window size.
- Removed the old textual recent-hitch timestamp list from Frametime; cumulative hitch counters remain.
- Graph shows ~8 seconds from `-8s` to `now`, with 33/50/100/200 ms guide lines.
- Uses 80 preallocated numeric samples at 10 Hz and stores the worst frame in each 100 ms bucket.
- Uses 80 textures created once at load; no texture creation occurs in the sampling/redraw path.
- Graph rendering is capped visually at 200 ms while numeric Worst remains exact.
- Graph data continues collecting while the window or another tab is shown; redraw occurs only while Graph is visible.
- Reset clears graph history with the other diagnostics.
- Pause stops graph sampling and periodic redraw work.
- Added `/perf graph` shortcut.

## Static / Automated Checks
- Manual compatibility review against the VanillaTemplate 1.12.1/Lua 5.0.3 rules.
- Current source contains 112 `local` tokens in total even with function-body locals included, still comfortably below the 200-local top-level compiler ceiling as a conservative gross count.
- Verified addon texture paths contain Lua-safe doubled backslashes in source.
- Verified 0.2.3 keeps the always-active driver frame, native `gcinfo()`, all four hitch thresholds and visibility SavedVariable behavior.
- Verified all graph textures are created before the driver `OnUpdate` path, the history uses a fixed ring buffer, sampling is 10 Hz, rendering is 5 Hz, old timestamp history code is removed, and Pause gates graph redraw.
- Canonical `tools/lua50/check_lua50.sh` compiler check not run in this chat because the GitHub connector does not provide the private template checkout as an executable filesystem tree.

## Current Issues
- No known runtime issues in the tested 0.2.1-dev baseline.
- 0.2.3-dev Graph tab was user-tested and described as working well; Frametime appeared unchanged/good.
- Follow-up in-game evidence showed Comms receiving and displaying addon traffic (`bcs`, count 1), resolving the earlier no-traffic discrepancy. No Comms code change was required.

## Testing

### Last Runtime Test
- Version/commit: `0.2.3-dev` / `b051fa642c35a49e809600903b96d0e4984d5b45`.
- Passed: Graph visual/scrolling, Frametime behavior, and Comms receive/count/display all confirmed working in-game. Comms visibly recorded prefix `bcs` with message count 1.
- Failed: None reported.
- Not tested: No additional runtime delta after 0.2.3.

### Next Runtime Test
- None required for the current 0.2.3 runtime state. Bind any future runtime test to the next version/commit that changes addon behavior.

## Planned / Next Work
- Current 0.2.3 feature set is accepted.
- Discuss the next scoped diagnostic feature before changing runtime code.
- Keep full event correlation as a separate later scope unless explicitly chosen next.

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
Discuss and agree the next feature scope; do not change the accepted 0.2.3 runtime until that scope is chosen.
