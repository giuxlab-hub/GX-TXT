# Changelog

## 1.3.3 — GX-TXT 0.9.8.10-dev

- Aligned the module version after the GX-TXT 0.9.8.09 runtime correction; scientific behavior is unchanged in this stabilization block.

## 1.3.2 — partial numerical migration

- Declare/discover NUMERIC_API_v1 through runtime metadata.
- Delegate FFT, one-sided extraction, detrend, window generation and frequency coordinates to the public service; preserve mean-relative timing acceptance.
- Accept only explicitly compatible existing cache schemas without relabeling their provenance.
- Preserve the current bounded-display-cache helpers and private renderer while public graphics migration remains open.
- Document unfinished work and missing real-Octave/large-session validation.

## 1.3.1

- Use CORE's base-module render-cache path for plot variants; write only presentation artifacts to the variant output directory.
- Accept compatible 1.3.0 scientific caches without recalculating FFT, while new scientific runs identify as 1.3.1.
- Require GX-TXT 0.9.7.82 `module_cache` variant semantics.
- Reject a presentation rerender when source bindings, Temporal Set or FFT scientific settings no longer match the cached fingerprint.
- Fix the real-Octave test harness cleanup so its service child is stopped before pipe closure.

## 1.3.0

- Enabled GX-TXT Plot Module API v1 variants for the time-frequency overview, 3D surface, and window-spectrum graph providers.
- Plot variants reuse the current base FFT Render Cache and never launch FFT workers merely to create another presentation.
- Variant artifacts, compact caches, individual window plots and extra formats remain isolated in the framework-owned per-variant output directory.
- Variant rerender is presentation-only and does not repeat optional scientific split-CSV export.
- Added regression coverage for descriptor-level variant support and variant cache reuse.

## 1.2.0

- Added `Run mode = Auto / Recalculate / Render only`.
- `Auto` now reuses a compatible scientific result and rerenders without repeating FFT workers.
- Added a scientific-input fingerprint covering source identity/stamp, bound variables, Temporal Set definition/members and FFT parameters; worker count and presentation settings do not invalidate the FFT cache.
- Reworked plotting around a compact bounded Render Cache generated while worker FFT values are already in memory.
- Normal overview, 3D and individual-window plots no longer reread the huge canonical long-form Dataset.
- Added common-grid display reduction with `peak` and `mean` modes.
- The full canonical Dataset remains unchanged and full resolution.
- Time-frequency 2D and 3D surface are enabled as normal global graph products.
- Window spectrum plotting now defaults to writing one separate file per selected window; selecting all 55 windows therefore produces 55 files rather than a multi-panel figure.
- The stable Window spectrum graph artifact defaults to a first-selected-window preview; overlay is explicit.
- Split CSV export remains optional and defaults to `none`.
- Fresh calculations produce requested split exports directly from worker results, avoiding a second Dataset scan.
- Render-only split export uses one streaming Dataset pass rather than rescanning the complete Dataset once per window.
- Expanded the standard module Help text with a practical Quick Guide explaining Window size, Step, overlap, Samples versus Duration, graph types and selection syntax.
- Expanded `MANUAL.md` with a detailed user-oriented guide and troubleshooting.

## 1.1.0

- Added module-owned plotting from the canonical published Dataset.
- Added time-frequency 2D overview, 3D surface and selected-window spectrum views.
- Added selected-window plot/export controls and optional per-window split CSV export.

## 1.0.1

- Fixed Octave worker argument parsing for real `octave-cli` process execution.

## 1.0.0

- Initial external plugin release.
