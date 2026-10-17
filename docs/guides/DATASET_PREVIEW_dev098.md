# Dataset Preview and metadata — GX-TXT 0.9.8.10-dev-098

Select a Dataset in the Dataset Browser and open **Preview**. The shared Preview
uses canonical Dataset access; its images and reduced display points are not new
scientific sources. **Open / scientific consultation** provides the interactive
plot and its Fit, zoom and pan controls.

## Filters and separate curves

**Configure filters / grouping…** lists every enabled, compatible rank-one
variable in the actual Variable Schema v3. Variable names, producing modules and
semantic roles do not restrict manual eligibility. Select a variable, choose a
predicate, enter its operand and add it. Remove a selected predicate to discard
it. All predicates combine with AND. Text comparisons are exact and case
sensitive. Numerical predicates retain their declared integer or floating type.
Missing and nonfinite numerical values follow the shared Graph Selection policy;
they do not become ordinary comparison operands.

Membership operands use a list of exact values. For example, `alpha beta`
selects either string, and `{Repeated label} Other` selects two strings including
one containing a space. Intervals use separate lower and upper operands.

Choose grouping variables independently from filtering variables. Each actual
combination becomes a separate series; unrelated curves are never joined merely
because they share X/Y variables. Choose the within-series ordering variable when
the source supplies one. With ambiguous membership and no reliable grouping,
configure grouping explicitly; acknowledging a single series is a deliberate
operator decision. Registered Digitalizer publications always retain stable curve
and calibration separation.

For published Digitalizer data, **Family**, **Curve** and, when present,
**Calibration** shortcuts resolve actual roles through the public schema API.
Family displays its source variable and units. Ctrl/Shift selects multiple values.
Curve labels include stable identities, so duplicate readable labels remain
distinct. Family and Curve selections combine. No genuine family parameter means
no invented Family selector. Apply the values, then Render / Plot.

Filters, grouping, axis choices and ordering use the existing Dataset metadata
configuration authority and travel with the Session. Reopening restores them.
Removed variables, changed types and stale complete value inventories are
reconciled against the current schema. An open editor cannot apply to a different
Session lifetime or changed schema. Distinct-value suggestions are bounded; a
partial suggestion inventory never removes a compatible variable from the manual
configuration interface. A bounded grouping budget reports a refusal rather than
silently drawing only some groups.

## Image, points and Quality

A legitimate Digitalizer publication shows its verified canonical source image,
original raster point overlay, stable curve table and Quality v2 information.
Show/Hide affects the raster and calibrated XY display; it changes no scientific
rows. Point counts deduplicate original point identities across calibration
realizations. Reduced raster displays use markers and report their retained/total
counts. Raster positions retain the source pixel geometry and aspect.

Only authenticated, geometry-preserving processed Image Datasets are offered as
alternative main images. Choose explicitly when multiple branches exist. With a
processed main image, the verified original appears at the bottom. Dataset IDs
are links through the existing guarded Dataset Browser. Missing or invalid
derivatives produce a visible fallback to the original; associations are never
guessed from filenames or dates.

Quality reports actual producer values and explanatory limitations. Diagnostic
flags and descriptive calibration spread are not physical standard uncertainties.
Missing Quality is unavailable information, never zero error. Open the full report
when a bounded summary is insufficient. The Preview neither recalibrates points
nor estimates new physical uncertainty.

## Bounds, ticks and navigation

Automatic Fit includes complete finite source bounds for every selected visible
series, including negative values. Bounded display reduction does not determine
those bounds. Display units are applied consistently to points and bounds. Fit
adds margins and may expand limits outward to convenient boundaries; it never
contracts them to remove data. Zero is not an assumed minimum.

Tick spacing adapts to the visible range, pixels and label size. Labels and grid
lines use the same true numerical coordinates. Short decimal or scientific
notation retains distinct tick values and avoids artificial negative zero.
Deliberate zoom and pan preserve a partial viewport and recalculate ticks; **Fit**
returns to complete selected data. Axis labels, limits and display reduction do
not change canonical values, physical units or point identities.

## Metadata

The existing **Metadata** page starts with **User** selected. Its compact group
selectors are discovered from the selected Dataset, not from all installed
modules. Select several groups to compare their fields. Module labels come from
the real represented producer descriptors. Unknown historical fields remain
visible under **Unclassified**; a textual prefix alone does not establish origin.

The generic editor edits User fields only. Saving merges those changes with the
current metadata and preserves producer-owned, reserved and unclassified values.
Module fields are read-only here. New publication and verified module callbacks
record origin through the canonical metadata authority. Existing uncertain
metadata is not rewritten to manufacture attribution.

Long table values show a bounded preview. Double-click a row to inspect the full
UTF-8 value and use **Copy full value**. Dataset and Session switching refresh the
available groups. Metadata presentation does not alter scientific payloads.

## Supplied modules and retired modules

Curve Digitalizer remains product **2.0.3**. Its original calibration, tracing,
processing, Workspaces and public APIs are retained. Zero localization uncertainty
is valid and remains exactly zero; undefined zero-variance correlations are not
reported as measured correlations. A fitter can still refuse an inadmissible
noise model, including all-zero independent variance or unqualified shared error.

Scientific Image Inspector remains product **0.4.1**, optional (`core=0`,
`default_enabled=0`). Enable/install it through the existing Plugin Manager and
open it from Viewers. Its complete supplied English manual remains in its module.
The official Linux candidate ZIPs are in `plugin_packages/official_dev098/`.
Same-version Update follows the existing installer policy; after uninstall,
Install accepts the candidate package. No new editor or layers/compositor is added.

`viewer.curve_trace_assistant` and `analysis.digitization_quality` are retired from
this distribution. Historical archives and Session documents remain preserved.
An unavailable historical provider is reported as unavailable; no replacement
alias silently opens a different module.
