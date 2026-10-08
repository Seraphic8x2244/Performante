# Development Progress

## Current
- Branch: `dev`
- Version: `0.4.0-dev`
- Accepted runtime baseline: `0.3.0-dev` single-client matrix passed at runtime commit `42d0ba7ec034958d77579ebe0884c6c02755694b` with metadata/localization completed by `38f168a2c469da0d15c7c599fcb938a2bfb8c8f5`; later documentation-only commits do not change that accepted runtime.
- Latest tested baseline: `0.3.0-dev` single-client runtime matrix described under Last Runtime Test.
- Stable baseline: None; `main` currently contains only the repository README.
- Goal: Preserve the accepted 0.3.0-dev runtime while completing all three agreed 0.4 diagnostic phases before requesting runtime testing.
- Current scope boundary: Phase 1 bounded capture is implemented. Phase 2 hitch/event correlation is the current implementation scope. Phase 3 Events/Correlation UI follows in the next development chat. Runtime testing is deliberately deferred until Phases 1-3 are complete; Phase 4 real-hitch investigation remains post-runtime.

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

### Agreed 0.3.0-dev Scope — Bidirectional Comms + Rates
- Preserve the accepted Comms / Frametime / Graph UI and the current 330x286 footprint.
- Expand Comms from received traffic only to separate **Inbound / Outbound / Total** accounting by communication prefix.
- Keep inbound accounting on `CHAT_MSG_ADDON` using `arg1` as the prefix.
- Add a lightweight hook/wrapper around the native `SendAddonMessage()` path so local addon sends can be counted before dispatch.
- The outbound hook is diagnostic only: it must preserve original arguments, return behavior and call order, and must not alter/throttle/block messages.
- Do not inspect/store payload bodies in 0.3.
- Do not add sender drill-down in 0.3.
- Add a recent **messages/second** rate so active spam is obvious even when lifetime totals are large.
- Rate calculation should use bounded fixed-window/bucket state rather than unbounded per-message history.
- The Comms display should remain compact; prefer concise columns/labels over a new full-size tab unless the existing tab cannot remain readable.
- Reset clears inbound/outbound totals and rate state with the other diagnostics.
- Pause stops both inbound/outbound counting and rate updates consistently with current global Pause semantics.
- Hidden-window collection continues as in 0.2.3.
- Keep Performante's own overhead low and avoid per-message table allocation where practical.
- Version target when runtime work begins: `0.3.0-dev`.
- 0.3 acceptance requires controlled tests for both directions:
  - receive a known `PERFTEST` message from another client and verify Inbound/Total/rate;
  - send a known message from the local client and verify Outbound/Total/rate;
  - confirm the hook does not break the actual addon message reaching its intended recipient.

### Agreed 0.4.x-dev Plan — Event Storm / Hitch Correlation
- Purpose: help answer **what was happening around a visible frametime hitch**, without pretending Vanilla can provide modern per-addon CPU attribution.
- This scope and stepped implementation plan were reviewed and approved by the user on 2026-10-08. On 2026-10-09 the user revised the validation sequence: implement Phases 1, 2 and 3 across bounded development handoffs first, then run one combined runtime gate. Keep each implementation phase scoped; do not pull Phase 3 UI into Phase 2.
- Event capture must be **explicitly armed/temporary**, never an always-on `RegisterAllEvents()` monitor.
- Prefer a short diagnostic capture window or bounded ring-buffer session with a clear active/inactive state.
- During capture, count event frequency/rate and retain only bounded summary/correlation data needed around hitches.
- Correlate captured event bursts with existing frametime/hitch timing so the user can see likely temporal associations.
- Do not claim causation from correlation alone.
- Avoid payload-heavy logging and avoid storing arbitrary event arguments unless a later design justifies a very narrow case.
- UI direction: likely a dedicated Events/Correlation view or an explicit capture mode; exact layout is intentionally undecided.
- Candidate outputs for later design review:
  - top events by count/rate during the capture;
  - events occurring in a short window around >50/>100/>200 ms hitches;
  - compact markers/summary tied to the existing Graph history;
  - capture duration/state and Performante overhead safeguards.
- Version target if/when this scope is approved after 0.3: `0.4.0-dev`.
- Full per-addon CPU attribution remains out of scope unless the target client exposes a trustworthy native mechanism; do not infer it from event counts.

#### Phase 1 — Bounded Temporary Event Capture
- Target first runtime revision: `0.4.0-dev`.
- Add explicit Start/Stop Capture state; broad event instrumentation exists only while capture is active.
- Register the selected diagnostic events on capture start and unregister them completely on stop.
- Count events in short fixed time buckets using bounded/preallocated state; do not build an unbounded per-occurrence event log.
- Track overall event counts/rates and capture duration/state.
- Integrate capture with Reset/Pause consistently; Pause must not silently keep diagnostic capture advancing.
- Keep payload/event-argument storage out of this phase.
- Include practical safeguards against Performante distorting the workload it measures.
- Deferred combined runtime gate after Phase 3 must verify events count, Stop removes extra instrumentation, capture does not cause obvious FPS/hitch regression, and all accepted 0.3 functionality still works.

#### Phase 2 — Hitch / Event Correlation
- Begin after Phase 1 implementation/static handoff; Phase 1 runtime validation is intentionally deferred until Phase 3 is complete.
- Correlate the bounded event buckets with existing frametime/hitch timing.
- Preserve compact summaries around significant hitches rather than raw event occurrence histories.
- Distinguish an **event-storm-associated hitch** from an **isolated hitch with no unusual event volume**; the latter is a useful diagnostic result, not a failure.
- Decide and document the correlation window from measurement/timing behavior before hard-coding it; do not assume an arbitrary +/-500 ms window.
- Report temporal association only, never causation.
- Deferred combined runtime gate after Phase 3 must generate known event activity and verify its timing/correlation against observed graph/hitch behavior.

#### Phase 3 — Diagnostic Events UI
- Begin after Phase 2 implementation/static handoff; capture and correlation runtime validation is intentionally deferred to the combined post-Phase-3 runtime gate.
- Add a compact dedicated Events/Correlation view rather than cluttering Comms or Graph.
- Candidate display: capture state/duration, top events by count/rate, hitch totals, worst hitch, and a compact summary of events around the worst/selected hitch.
- Keep controls explicit and the normal non-capture monitoring path cheap.
- Runtime gate: UI/control behavior, real gameplay capture, Graph interaction, Pause/Reset, hidden-window behavior where applicable, and full regression of accepted diagnostics.

#### Phase 4 — Real Hitch Investigation / Evidence-Driven Refinement
- Use the completed diagnostic build during actual gameplay to reproduce the user's real hitches.
- Inspect whether hitches repeatedly coincide with event storms or occur with normal event volume.
- If a particular event family is implicated, use that evidence to choose the next narrow diagnostic/investigation.
- If event volume is normal, record that result and investigate a different mechanism rather than adding more event logging.
- Make only evidence-driven `0.4.x-dev` refinements; do not pre-design speculative attribution features.

#### Chat / Handoff Boundaries
- Plan for four development chats: Phase 1 capture engine; Phase 2 correlation; Phase 3 UI; Phase 4 real-hitch investigation/refinement.
- Finish Phases 1 and 2 with static checks plus an explicit untested handoff. Finish Phase 3 with static checks, then request one combined runtime matrix covering all three phases before Phase 4 begins.
- Meaningful runtime revisions must bump the `.toc` development version per `dev_rulebook.md`; expected progression is `0.4.0-dev`, then `0.4.1-dev`, `0.4.2-dev` as needed rather than one unversioned multi-chat build.
- Do not begin Phase 3 during the Phase 2 chat. The handoff boundary, rather than an intermediate runtime gate, controls progression through Phases 1-3. Phase 4 remains blocked on the combined runtime acceptance.


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
- `dev`: `b051fa642c35a49e809600903b96d0e4984d5b45` — 0.2.3-dev; Graph-tab build, additionally suppressing periodic redraw work while paused.
- `dev`: `855bc182b94a719ef8e893a17af35f29aed9b4e6` — 0.4.0-dev Phase 1 runtime implementation complete after lexical-scope correction and version bump; awaiting runtime test.

## Completed / User-Verified
- The precursor AddonCommsMonitor 0.1.0 was used by the user and its compact live layout was accepted.
- The 0.2 feature plan above has been accepted by the user.
- Performante 0.1.0-dev at `c06d6b71f2296d92a8ecbcba1f13f977841551cc` was user-tested after the rename/repackage and reported working.
- Performante 0.1.1-dev at `bcd1e20784f9c230f5134e2ba589c5037c6d4c45` was user-tested: visibility persistence worked across reload and the existing monitor remained functional.
- Performante 0.2.1-dev at `3727265ccc03a638b47be91bc41223df5ff4a358` was user-tested: Comms, Frametime, hitch counters/history, memory display, Reset/Pause, hidden-window collection and open/closed persistence all appeared to work.

## Implemented / Awaiting Runtime Test
- 0.4.0-dev Phase 1 adds an explicit temporary capture engine controlled by `/perf capture start`, `/perf capture stop` and `/perf capture status`; no Events UI was added.
- Capture registers a fixed selected set of 42 high-activity Vanilla events only while active and unregisters all of them on Stop.
- Capture data is bounded: ten preallocated 0.5-second buckets per selected event, overall counts, recent five-second rates and capture duration. No event payloads/arguments or per-occurrence log are stored.
- A 30-second hard safety limit automatically stops capture to bound instrumentation overhead.
- Pause freezes capture counting and duration while preserving the armed state; Resume continues it. Reset clears capture summaries/duration consistently with the other diagnostics.
- Status output reports active/stopped state, duration, total events and the top five events by count/rate through chat only; this is a Phase 1 test/diagnostic surface, not the deferred Phase 3 Events UI.
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
- 0.4.0-dev Phase 1 static scope checks passed: version metadata is 0.4.0-dev; Start/Stop/Status paths exist; selected events are fully unregistered on Stop; capture is bounded to 10 x 0.5-second buckets and 30 seconds; Pause gates capture; Reset clears capture state; no payload storage and no `RegisterAllEvents()` path were introduced.
- Conservative gross `local` token count for current `Performante.lua`: 164, below the Lua 5.0.3 200-local function/chunk ceiling; this is not a compiler pass.
- Static inspection found and fixed one pre-runtime lexical-scope defect where capture readiness initially bound to a global instead of the existing local `monitoringReady`.
- Manual compatibility review against the VanillaTemplate 1.12.1/Lua 5.0.3 rules.
- Verified addon texture paths contain Lua-safe doubled backslashes in source.
- Verified 0.2.3 keeps the always-active driver frame, native `gcinfo()`, all four hitch thresholds and visibility SavedVariable behavior.
- Verified all graph textures are created before the driver `OnUpdate` path, the history uses a fixed ring buffer, sampling is 10 Hz, rendering is 5 Hz, old timestamp history code is removed, and Pause gates graph redraw.
- Canonical `tools/lua50/check_lua50.sh` compiler check not run in this chat because the GitHub connector does not provide the private template checkout as an executable filesystem tree.

## Current Issues
- No known runtime issues in the accepted 0.3.0-dev single-client baseline.
- 0.4.0-dev Phase 1 has no known static defects after the readiness-scope correction; runtime behavior is not yet user-tested.

## Testing

### Last Runtime Test
- Version/runtime commit: `0.3.0-dev` / `42d0ba7ec034958d77579ebe0884c6c02755694b` (runtime Lua), metadata/localization completed by `38f168a2c469da0d15c7c599fcb938a2bfb8c8f5`; status head `0c9771a49b6c7ebc05b4dc632c49b3e2491b2c9f`.
- Passed (user, single client): compact columns fit; PERFTEST inbound/outbound/total counted; 20-message PARTY burst increased outbound and rate; rate decayed to zero; Pause/Resume and Reset; collection while window hidden; Frametime current/worst, hitch counters and memory; Graph scrolling/spikes and Pause/Resume.
- Failed: None reported.
- Not tested: Delivery to another client/recipient; Lua 5.0.3 canonical compiler check not run. Local self-receipt does not prove remote delivery.

### Next Runtime Test
- 0.4.0-dev Phase 1 gate, single client:
  1. Confirm accepted Comms / Frametime / Graph behavior still works before capture.
  2. Run `/perf capture start`, generate ordinary activity/combat, then `/perf capture status`; verify duration/total/top-event counts advance.
  3. Pause during an active capture, wait and generate activity, check status, then Resume; verify capture duration/counts did not advance while paused and continue after Resume.
  4. Run `/perf capture stop`, generate more activity, then `/perf capture status`; verify counts/duration remain unchanged, demonstrating extra event instrumentation was removed.
  5. Start a fresh capture and let it reach 30 seconds; verify the safety stop message and stopped status.
  6. During capture, watch Frametime/Graph for an obvious FPS/hitch regression compared with the accepted baseline.
  7. Recheck 0.3 PERFTEST outbound/total/rate plus Reset and hidden-window collection.
- Cross-client PERFTEST delivery remains optional 0.3 validation debt when a second client becomes available.

## Planned / Next Work
- 0.3.0-dev single-client behavior is the inherited accepted runtime baseline; cross-client delivery remains untested.
- 0.4.0-dev Phase 1 bounded temporary event capture is implemented and statically reviewed, awaiting the runtime gate above.
- Phase 2 correlation remains blocked until the user accepts the Phase 1 runtime result.

## Deferred / Out of Scope
- 0.4 later phases remain gated: Phase 2 correlation, Phase 3 UI and Phase 4 evidence-driven refinement must not be pulled into Phase 1.
- Any always-on `RegisterAllEvents()` design.
- Sender drill-down and payload storage in 0.3.
- Persisted counters or historical sessions.
- Per-addon CPU attribution that the native 1.12.1 client cannot provide directly.

## Release / Promotion Notes
- Main-only or release-only content to preserve: current repository README.
- Validation debt: cross-client delivery untested, Lua 5.0.3 canonical compiler check not run; no stable release authorized.
- External/runtime prerequisites: None beyond a Vanilla WoW 1.12.1-compatible client.

## Exact Next Step
Runtime-test 0.4.0-dev Phase 1 using the seven checks above. Fix only demonstrated Phase 1 defects. Do not start Phase 2 hitch correlation or Phase 3 Events UI until this runtime gate is accepted. Cross-client PERFTEST delivery and the Lua 5.0.3 compiler check remain validation debt.

## 0.3 Implementation Status
- Implemented native SendAddonMessage diagnostic wrapper and received CHAT_MSG_ADDON accounting, grouped by prefix, with In/Out/Total and five-second messages/sec columns in the unchanged Comms tab footprint.
- Counts and rate buckets are session/reset scoped; Pause freezes the diagnostic clock and collection. Payloads are not stored.
- Single-client runtime checks user-tested and passed on 2026-10-07. Remote recipient delivery not tested. Lua 5.0.3 compiler check not run; connector access does not expose a runnable checkout. 0.4 Phase 1 is implemented and awaiting runtime test; later phases remain gated.
