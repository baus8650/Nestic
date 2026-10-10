# Performance audit — October 8, 2026

Reviewed navigation, Home, Record/Insights, activity, reports, photo rendering, store refreshes, and widget/Watch publication paths. This is a source audit with simulator regression checks and a model benchmark; it is not a claim that every device or dataset has been profiled with Instruments.

## Findings and changes

- **Record → Insights:** Forecast getters were fitting models during SwiftUI rendering. Each timeline row read all forecasts twice; opening the forecast card could also publish widgets and fit every subject again. Forecasts now reuse a subject's results within the current minute. Entries, subjects, trackers, preferences, quiet hours, nest selection, and scored outcomes invalidate the cache. Unscored audit snapshots do not. Recording a forecast no longer republishes all widgets.
- **Model fitting:** Tracker history is grouped once, covariance terms are computed once per symmetric pair, and models with more features than samples solve an equivalent centered ridge system in sample space. The intercept remains unpenalized and regularization stays at 0.12.
- **Graphs:** Today's graph prepares forecasts and event groups once. Weekly/monthly counts use dictionary lookups instead of repeatedly regenerating all points for each bar. Calendar history and totals aggregate in one pass.
- **History and activity:** Subject history is sorted/grouped once per data change. Subject/tracker lookups use invalidated indexes. Record history renders lazily. Activity filters once, skips search-string construction when search is empty, and groups matching entries once per render.
- **Reports:** Episode summary statistics are prepared once per render. Additional tracker histories share grouped chronological entries, and tracker counts are aggregated once.
- **Photos:** Avatar and event-photo decoding use bounded, evictable image caches (24 MiB/64 avatars and 48 MiB/32 event images). Saving or removing an event photo invalidates its decoded cache entry.
- **Network refresh:** Existing refresh coalescing, independent main snapshot requests, pagination, and generation checks are retained. Optional settings/reminder/forecast reads now run concurrently instead of in three serial round trips.
- **Widgets:** Identical payloads do not trigger redundant timeline reloads. Five-minute clock entries reuse snapshots until midnight or a cached forecast passes, instead of rebuilding history for every clock position.

## Measurements

A release-optimized standalone benchmark used one subject, 12 trackers, 480 timestamped events with varying gaps, and 25 fits per implementation. On this development machine, median fit time changed from **6.24 ms to 2.15 ms** (approximately **65% lower**). This measures model CPU work, not screen latency on a physical iPad.

The optimized engine was compared against the pre-audit engine on **16 fixtures** spanning 0/1/3/11 input trackers and 4/8/40/80 target events. Model choice, sample count, confidence, and timing window matched within numerical tolerance. The largest interval difference was **7.02 × 10⁻¹⁴ hours**.

## Verification

- Simulator app/widget build.
- Core regression tests, including new tests for reuse within a minute and invalidation after time advances, new logs, scored outcomes, preference changes, quiet-hour changes, and sign-out.
- iPad simulator performance test repeatedly switches Record → Insights → Record and checks both displayed content and selection state.
- Whitespace checks.

## Practical limits

Forecast results may be reused for the remainder of the current minute; actual data/settings changes invalidate immediately. iOS still controls widget update delivery. Network improvements reduce independent request serialization but were not benchmarked against the production backend. The screen-switch test includes XCTest interaction overhead and is a regression check, not a pure frame-time measurement. Physical-device frame, memory, and cold-launch profiling remains unmeasured.
