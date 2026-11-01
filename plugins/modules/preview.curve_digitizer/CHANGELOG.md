## 0.1.12 (2026-10-31) — prepared-cache-only async Preview

- GUI Curves loads the already-prepared, source-validated CORE Preview native model via public host adapter. On miss it subscribes to CORE's off-GUI managed worker, with no repeated canonical grouping on selection/reopen.
- Canonical Data pages are provided through the public CORE cache page service, with a persistent Session-bound SHA-validated page and asynchronous worker on miss, plus existing two-page GUI memory for precision changes.
- Calibration & Quality / Source image retain the existing CORE prepared cache owner.
- Requires the additive CORE Preview Cache Bridge 022 patch. No direct private cache reads from plugin.
- No Dataset or Session format/API mutation.
\n## 0.1.11 (2026-10-31)

- Correct Calibration ID and label for Separate calibration publications using declared producer metadata, with consistency checks against measurement metadata. Keep per-row keys for Combined datasets.
- All canonical scientific values and uncertainty columns remain unchanged.

## 0.1.10 (2026-10-31)

- Display declared uncertainty variables in Canonical Data using public Variable Schema semantic roles and matching physical units.
- Retain up to two verified bounded canonical pages per live Preview host to avoid redundant reads on numeric precision changes and back/forward navigation.
- CORE Preview durable cache remains under CORE authority; no edits to CORE, publication or scientific values.

## 0.1.9 (2026-10-31)

- The Canonical Data Point traceability table resolves producer-declared point_id mapping using authorized Preview metadata and validates the referenced Dataset Variable Schema v3 ID; presents full stable point identifiers from bounded public canonical pages.
- No schema/CORE modification, guessed fixed column positions, or raw file parsing.

## 0.1.8 (2026-10-31)

- Compact Canonical Data toolbar: natural-sized Load/Prev/Next, expandable spacer, compact Precision label and fixed-width native combobox.
- Removed the automatic Reset action from the precision choice by replacing it with the public read-only combobox component.
- All paging, numerical representation, canonical source and Plot v4 behavior unchanged.

## 0.1.7 (2026-10-31)

- Canonical Data now uses separate scientific/traceability UI Field read-only tables, bounded public Dataset pages, and visual precision controls. CORE unchanged.

## 0.1.6 — Native Plot v4 on logical Y1/Y2

- The producer's public Dataset Schema adapter supplies typed Y-axis roles.
- Bounded canonical rows include the Y axis ID and preserve curve and
  calibration identities without any private file reader.
- Plot Dataset API v4 uses left for Y1 and right for Y2, while the logical
  digitizer axes remain independent of physical left/right placement.
- Valid X/Y logarithmic display scales and scientific axis labels are
  retained through metadata. Legacy schema 0/1 Preview behavior is unchanged.
- An isolated Tk/Plot-v4 prepared-model test verifies both axis bindings.

# 0.1.5 — DEV111-P031

P0310.1.5 is a separately versioned presentation correction of the retained
owner0.1.4 input: two control-character caption separators become em dashes,
and the readonly Dataset identity wraps without taking half the curve-list
width. The runtime api/preview.tcl and all scientific/schema/Plot operations
remain byte-identical to0.1.4. Original ZIP SHA256 c07ae52b27dd81737eb2f95acaf842eb56e6c48f6eccdc6722b41d854335cfac.
Independent final P031 acceptance is required; the original historical
validation below is not claimed as acceptance of this corrective package.

## 0.1.4 — Explicit Curves selection and Preview lifecycle

- Initialize the Curves list with a clear, non-scientific placeholder
  instead of an unexplained blank box. Clicking it triggers the same
  source-bound Load action as the Load curves button.
- Keep scientific reads OUT of guiMount; the first user action schedules
  the existing bounded cooperative page reader.
- No CORE cache extension, no changes to scientific Dataset/Session data;
  native Plot v4 continues to own rendering.

## 0.1.4 — Tcl Preview action dispatch validation

- Fix a Tcl switch parsing error in the Preview controls dispatcher.
  The previous inline ';#' comment was parsed as extra switch patterns,
  breaking every action originating from the Curves GUI.
- Preserve the existing Tk GUI layout, separate canonical table and native
  Plot Dataset API v4 renderer. No CORE or Dataset changes.
- Add an explicit regression of the actual generated GUI event callback,
  covering Load curves, passive selection and Plot v4 visibility.

## 0.1.4

- GUI: async-cooperative canonical page scan with a bounded work step per
  Tk event, progress status, stale Session/source cancellation and disposal.
- CORE Native2D C++ Plot API v4 remains the exclusive graph renderer.
- Repeated Load cancels its prior coroutine. No nested update(), no CORE
  thread/scheduler override, no direct private scientific file I/O.
- More compact Curve selector, stable GUI control identity.

## 0.1.4

- Correct the Preview-target GUI design contract syntax: the real
  GX-TXT Builder validator requires semicolon-separated Dataset contracts.
- This repairs the observed GUI mount refusal:
  Invalid canonical Dataset contract ID.
- Add live-host design validation and regression guarding the serialized
  GUI design (previous synthetic stub allowed invalid contract strings).
- Preserve all 0.1.0 preview functionality; no CORE changes.

## 0.1.4

- Three-tab read-only Dataset Preview contribution, independent install.
- Preview-target Viewer Interface Builder GUI, native Plot Dataset API v4.
- Source-bound per-curve/calibration visibility; published quality metadata.
- Canonical CORE Dataset Preview table, no private dataset readers.
- No CORE edits.
