# COMPARISON_PLOT_API_v1

CORE owns optional, domain-neutral curve comparison using the existing Numeric
service and native Plot Dataset v4. This API does not publish scientific data,
identify a material, administer Libraries or grant arbitrary Tcl/filesystem access.

`comparisonPlotApiInfo` describes actual operations and bounds. Trusted hosts use
`comparisonPlotSourceDataset(dataset,x_variable_id,y_variable_id)` or
`comparisonPlotSourceLibrary(library_id,entry_id)` to capture an immutable read
pin. Dataset pins retain canonical payload/schema hashes, the SHA-256 digest of
the complete authority-owned portable revision (never a truncated record),
Session origin, coordinate/metadata/provenance identity, units and actual Variable
IDs. Library pins retain managed Library/entry identity, revision, payload hash,
scientific metadata and provenance. No samples or absolute source paths are
stored in these pins. Missing or changed sources require explicit reselection.

Each source contains 2–65536 actual samples; 2–8 distinct sources are admitted.
There is no silent truncation or display reduction before numerical comparison.
Calculations and coordinate conversion use the existing Numeric binary64
floating-point semantics. Authoritative int64/uint64 samples outside
[-9007199254740991,9007199254740991] explicitly refuse before conversion, never
silently round. This API does not promise exact wide-integer arithmetic.
Library consultation uses the existing Manager's read-only content policy and
exact pages of at most 32768 samples. A provider lacking an admitted bounded
scientific curve representation refuses explicitly. No Dataset is created while
consulting a Library, and rights are not changed or inferred.
Library identity pins can be captured without an open Session using the existing
pure UTF-8 byte hash, without a working-directory cache. Prepared Plot widgets
and Workspace still require the existing Session lifecycle in this version;
capturing a pin does not grant a Session-free Plot or Workspace context.

`comparisonPlotValidate(configuration)` validates a configuration and all current
source pins. The configuration schema is `GXTXT_COMPARISON_PLOT_v1`:

| Field | Meaning |
| --- | --- |
| `sources` | Ordered list of pins from the public source operations |
| `mode` | `overlay`, `top_bottom`, `stacked`, `difference`, `ratio` |
| `normalization` | `none` by default; optional display-only `minmax` |
| `offset` | Finite per-source Stacked display step; otherwise zero |
| `denominator_floor` | Nonnegative absolute denominator exclusion threshold |
| `interpolation` | `linear` |
| `domain` | `intersection_first_source_grid` |

Overlay and Stacked may show explicit min-max display normalization. Constant
finite traces normalize to zero. Raw scientific samples remain unchanged.
Top/Bottom uses raw, separately labeled Y scales and shared X interaction.
Different physical Y meanings may be inspected in separate Top/Bottom panels;
raw shared-axis and derived comparisons require compatible ordinate meanings and
units. Compatible unit conversion uses the existing unit registry. There is no
implicit representation conversion (for example transmittance into absorbance),
unknown-unit equivalence, time-origin alignment or extrapolation.

Difference and Ratio require exactly two ordered sources and raw normalization.
Numeric preserves the first source's order and uses its coordinates inside the
common domain, linearly interpolating the second source without extrapolation.
Descending and irregular strictly monotonic coordinates are supported. Duplicate
or nonfinite X coordinates refuse. Nonfinite Y samples retain gaps: interpolation
does not bridge missing brackets; existing exact finite knots remain valid.
Difference is first minus second in the first ordinate's unit. Ratio is first
divided by second after conversion to that common unit, hence dimensionless.
Nonfinite or zero/near-zero denominators produce gaps and diagnostics, not
invented values or continuity. No independent identification is implied.

`comparisonPlotPrepare(configuration)` returns `{model ..., receipt ...}` after
source reads, Numeric preparation and a second source/lifetime check. The model
is transient presentation, not canonical Dataset rows. `comparisonPlotSpec`
returns the ordinary persistent PlotSpec with its versioned comparison
configuration. Plot v4 prepares this spec using the same native renderer and
validates pins before live operations. Existing PlotSpec, Document/Graph
resources, Workspace, History and variants remain the persistence owners.
Workspace cold restoration refuses changed/missing references.
Actual renderer admission also requires the loaded native backend to declare
shared-X and atomic view/restore capabilities. A mixed installation or stale
override cannot silently claim those behaviors; it explicitly refuses before
replacing the valid frame. `PlotDatasetAPIv4::nativeBackendInfo` reports the actual
loaded implementation, independently of a file path supplied in the environment.

Builder exposes **File > New Comparison Viewer…**, a normal section/Plot profile
with source and method tabs, ordered source table, status and primary Compare
menu. A reciprocal `comparison_form`/`comparison_target` association prevents a
second binding owner (`plot_form`) from controlling that Plot. Optional source
selection is ordinary UI draft state in the existing Workspace; no scientific
sample cache or second Registry is created.

The restricted C++ SDK adds `Host::comparison_command(form,operation)` and
`Host::comparison_result()`. Operations are finite: `discover`, `add_dataset`,
`add_library`, `remove`, `up`, `down`, `prepare`, `clear`, `inspect`,
`plot_fit`, `plot_zoom_in`, `plot_zoom_out`, `plot_cursor`,
`plot_clear_cursor`, `plot_reverse_x`, `plot_properties`, `plot_legend`,
`plot_style`, `plot_copy`, `plot_export`, `plot_save_variant`,
`plot_load_variant`. Commands
read declared controls; C++ supplies no samples, paths, Tcl or scientific math.
The result is an immutable next-event status/error/sequence receipt. A returned
receipt is not authority. Admission requires actual
`COMPARISON_PLOT_API_v1/comparison_command`, native Plot capability, exact Numeric
`comparison_curves` capability for preparation, and separate read-only Manager
grants for Library consultation. Missing capabilities explicitly refuse.
Actions must match declared presentation handlers and current installed package,
source, Session, window and event lifetime. Existing SDK v1 Event/State/Host
layout and previous adapter bodies remain compatible.

The separately supplied owner Curve Digitizer modules are not test producers
for this API. Their qualification remains
`OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST`.


## Shared Plot presentation (P034)

The Builder Comparison profile declares a primary Plot menu for these thirteen
presentation operations. They act on its reciprocal comparison target through the
existing finite command service; capabilities, declared actions, current native
host, Session and source pins remain mandatory. Commands take no producer paths,
samples or arbitrary Tcl. Unprepared plots refuse except Load Variant, which lists
only actual saved Comparison variants. History browsing permits navigation and
image copy/export, while scientific presentation edits require the latest state.

Properties edit shared X and the selected independent Y axis, panel title and
fonts. Legend and per-display-series styles use existing native presentation.
Version1 scalar keys in `native_presentation.plot_config` are
`comparison_style_version=1` and
`comparison_style:comparison_N:{color,line_width,line_style,marker,marker_size,opacity}`.
They are validated against the actual mode/source count and the existing Plot
style contract. Existing PlotSpec typed Workspace and Graph variants persist them;
no scientific payload or second store is created. Stale dialogs and source pins
refuse rather than silently changing the prepared frame.

The opt-in cursor marks actual displayed X/Y coordinates after the declared
comparison transform. It makes no claim to identify a canonical source row.
Copy uses the existing X11 image clipboard. Export uses a normal PNG Save dialog,
managed operation resource and File Publication owner. Save/Load Variant use the
existing Graph variant service and revalidate exact scientific source identities.

CORE-owned properties and cursor callbacks retain their admitted module/package
and source snapshots after the initiating native event. They recheck current
package/source identities and Comparison/Plot grants. Re-preparation additionally
requires `NUMERIC_API_v1/comparison_curves`; any bound or loaded Library source
retains its separately admitted read-only Library capabilities. A changed
package or revoked capability refuses before replacing the valid Plot.

A refused admitted Comparison intent seals a fresh `failed`/null receipt and
propagates its bounded public error to the existing native action/footer owner.
Deliberate Export chooser cancellation seals `cancelled`/null; it neither writes
a file nor fabricates a failed publication. Opening a CORE-owned properties or
variant dialog is a completed `dialog_opened` intent; applying its values is
separately guarded by the captured current source/package identities.

The display cursor persists as four finite scalar fields in the existing native
presentation map: `comparison_cursor_version=1`, `comparison_cursor_panel` (an
actual declared panel ID), `comparison_cursor_x` and `comparison_cursor_y`. All
four must occur together, with finite coordinates. CORE projects disposable
reference lines into the derived render model. Pick/Clear never rewrite user
annotations or depend on an annotation ID, which the public Graph annotation
contract does not persist. Existing Graph variants and typed Workspace preserve
the cursor fields together with the exact scientific source pins.

Presentation forms accept the existing Graph-normalized values after cold load:
blank inherited font sizes, automatic axis/legend choices, Boolean legend border
and standard RGB color casing. Unedited Apply preserves inheritance and the
stored font units. Changing another legend property validates a genuine color
through the existing UI Field owner; no second graph normalization is introduced.

### Shared Browser selection (additive P035)

A Comparison section may declare `comparison_library_browser_group` naming a
complete records/sources/manual `library_browser` group in the same design.
Declare a distinct presentation handler mapped to `add_browser` in
`comparison_commands`. `Host::comparison_command(form, "add_browser")` uses the
shared Browser's currently selected **and inspected** Entry, including pages
beyond the legacy 200-entry choices. It does not publish/import a Dataset.

CORE validates the Browser's scope, provider availability, current domain
revision/content SHA and normal scientific Library pin before admission.
A changed or uninspected selection, missing Library capability, duplicate source
or ninth source refuses without replacing the last valid Plot. Existing
`add_library` and all original Comparison operations remain compatible.

The next-event `comparison_result().result.selected_source` is a bounded typed
record: library_id, entry_id, library_version, payload_sha256, semantic_sha256,
entry_revision, content_sha256, provider_id, source_id, session_token,
window_lifetime and event_generation. This observational receipt grants no
authority; no paths or sample arrays are exposed and consumers must reselect
after relevant identities change. The ordinary separate Library Manager, Plot
and Numeric grants and exact declared event/package checks remain mandatory.

### Library-only consultation without a Session (P035)

`comparisonPlotPrepare` and normal Plot v4 widgets can compare only managed
`library_entry` sources with no Session open. CORE retains the existing process
context epoch; opening or closing a Session invalidates the earlier native
consultation context, including an open/close roundtrip. No canonical Dataset,
Session directory, Workspace or catalog subscription is manufactured. All real
source pins, bounds, Numeric semantics and native Plot interaction remain in
their original public owners. Dataset sources and other Plot kinds retain their
Session requirement. Save/load Plot Variants and Session Workspace/History remain
Session operations; consultation does not implicitly publish a Dataset.

For a Browser-only Comparison profile, `comparison_library` and
`comparison_entry` may both be omitted when a complete
`comparison_library_browser_group` is declared and no `add_library` handler is
declared. Discovery then uses the shared paginated Browser and does not populate
a second legacy Library/Entry selector. Existing profiles and explicit
`add_library` retain both controls and their original bounded discovery.

`add_opened` is a separate optional presentation handler with the same bounded
selected-source receipt. It consumes an actual `library_id` + `entry_id` context
passed through ordinary Manager/Viewer opening. CORE revalidates that reference
inside the declared Browser group's scope before adding it. Opening accepts
Library identity alone for consultation; an Entry action additionally requires
an actual current bounded scientific Entry. No default Entry or scientific query
is invented, and an incompatible scope refuses explicitly.

A profile may explicitly set `comparison_single_source=1`, producing the additive
configuration flag `single_source_consultation=1`. This allows one real source in
Overlay, Top/Bottom or Stacked as a consultation view. Ordinary configurations
retain the two-source minimum; Difference and Ratio always require exactly two
ordered sources. No empty/fabricated reference, duplicate or scientific
publication is introduced. Library-only no-Session authority remains unchanged;
a canonical Dataset still requires its real Session.

Newly prepared Comparison specs use the existing shared Graph legend to the right of the
scientific panel, with stacked entries, to avoid obscuring signal
peaks. Existing saved specs and explicit legend dialog choices retain their
stored presentation. Stacked offset captions use12 significant display digits;
full configuration/receipt values, numerical coordinates and scientific source
identities are unchanged. No renderer or Native2D implementation is modified.

The strict native Workspace comparison configuration codec admits the optional
boolean `single_source_consultation`. Old states without it retain the ordinary
two-source default; the explicit opt-in survives Save/Reopen/History without
relaxing unknown-field, scientific source, schema or revision checks.

Long repeated method prose is displayed in the existing panel caption rather
than appended to each legend source name. Stacked shows its exact display step
and first offset0; original source labels stay intact. Difference/Ratio use
`Source 0 − Source 1 (display)` / `Source 0 ÷ Source 1 (display)`, matching the
existing zero-based ordered Sources table. The complete names, Dataset/Library
identities, scientific pins and method configuration remain in that table, its
inspectors and the existing comparison receipt. No source identity or numeric
value is shortened or replaced; this is presentation only.

Both Plot Variant Save and Load require a real current Session. Save also
requires the existing admitted prepared Plot; Load may select an existing
Session variant before preparing one. Library-only consultation keeps Fit,
Zoom, Copy and PNG Export available without creating a synthetic Session.

Loading a saved Comparison variant does not depend on first mapping/drawing
the previous Plot tab. The explicit replacement path does not request a native
axes receipt for a view it will not retain. The original Session, variant,
source, package and History admission checks remain unchanged; failed loading
retains the previous valid scientific Plot. Ordinary view-preserving edits keep
their existing native-axis capture and restore behavior.

New Comparison Plot specifications place the full source legends below each
panel in one column through the existing shared Graph presentation. The footer
margin grows with the displayed series count (one per panel for Top/Bottom and
one derived series for Difference/Ratio). This avoids clipping long canonical
Dataset or reference names in the fixed right strip and keeps legends outside
the scientific traces. SourceRef labels, identities, saved configurations,
scientific values and the native renderer remain unchanged. Existing saved
specifications and explicit Graph presentation choices retain their settings.
