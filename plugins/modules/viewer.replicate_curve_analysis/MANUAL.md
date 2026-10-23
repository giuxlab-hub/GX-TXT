# Replicate / Consensus Curves

Open **Viewers → Replicate / Consensus Curves**. Opening performs no analysis and
does not enable the optional legacy Replicate Analysis. The Viewer uses the same
public Numeric replicate/statistical engine as the retained Analysis interface.
The public scientific service orchestrates the registered Numeric and Statistics
providers through managed Jobs.

The top toolbar provides Add source, Analyze/Cancel, Undo/Redo, Fit, Zoom and Save.
Sources, Study, Edit and View menus share the same commands and shortcuts.
The left inspector scrolls; drag its splitter to give the live canvas more space.
Workspace and Description/History use the common CORE lifecycle. Source dialogs
provide Cancel and Escape; F1 opens this guide.

Declare a study ID, method, design, common physical frame and units. Confirm the
frame only after verifying the physical alignment. Matching unit strings do not
establish a common frame. Add sources using canonical Dataset and Variable IDs,
observation/point-set/calibration/source-group identities and one physical feature.
Different edges require different studies even when stored in one Dataset.

Use **yx** for strictly increasing X traces with a shared X domain. Use **xy_path**
for ordered open/returning or closed paths. Declare the order Variable, topology,
corresponding physical start landmark, traversal direction and closed-path phase
index. Correspondence is explicitly anchored normalized source chord length,
evaluated by CORE's parametric spline. It is suitable only when that physical
correspondence is justified. Crossing, overlapping, degenerate or incompatible
paths fail explicitly. A smooth curve alone does not prove valid correspondence.

Choose **repeatability** only for independent observations and point sets.
**calibration_sensitivity** uses multiple calibrations of one observation/point
set and counts one independent observation. **hierarchical** requires multiple
source groups and repeats within sources. Descriptive sample dispersion, conditional
independent SEM and identifiable Numeric within/between-source components are
separate quantities. Shared calibration covariance, confidence/prediction intervals
and a covariance-aware shared-factor estimator are explicitly unavailable. Exact
zero localization uncertainty stays zero. Do not interpret sensitivity spread as
SEM or a confidence band.

Press **Analyze** to submit a managed Python Job; Cancel uses the existing Jobs
supervisor. Results are adopted only if Session/source/script identities remain
valid. The canvas shows consensus and actual original observations. Wheel zooms,
middle drag pans and Fit restores bounds. Curve checkboxes retain native buffers;
they do not rerun science. Native picks report genuine source identities/rows.
The inspector shows the qualifications alongside the result.

**Publish results** creates three new canonical Datasets under
`module/curve.replicate_analysis/studies/<study-id>`: profile, original/aligned
traces, and feature summary. Publication is atomic and create-only. Choose a new
study ID for a separate study. Original rows keep their canonical ordinals;
aligned derived samples use explicit source-row `-1`. Profile metadata contains
full role/Variable and statistical bindings; linked trace/summary prototypes are
clearly scoped reference interpretation. **Publish Graph** creates an editable
GX-TXT Plot v4 Graph Variant. Existing Analysis Dataset and Graph IDs stay intact.

Save Workspace to retain the recipe, results, visibility, view and Graph reference.
Save before adopting a large result; receipts above 512 KiB use the Workspace's
managed resources. An unsaved large result remains in the completed Job when
adoption refuses; save and explicitly Analyze again. Saved unpublished results
require a fresh Analyze before new canonical publication after reopening; saved
published outputs/Graphs retain their ordinary lifecycle. Scripts/jobs never run
merely because a Workspace opens. F1 opens this guide.

Bounds: 1–64 traces, 65536 canonical points per trace, 3–2048 aligned grid points,
32 MiB encoded control receipt. Native topology validation accepts at most 4096
vertices; denser XY paths fail rather than silently reducing scientific geometry.
These are bounded supported contracts, not unlimited geometry promises.


### Editing retained sources

Generic Add/Edit retains the original trace and changes only displayed fields
actually edited. Filters, coordinate context, source revision, unknown metadata
and absent optional defaults survive a no-op; Cancel keeps the original. Mapping
changes that would reinterpret an existing prepared recipe are refused. A saved
unknown source-binding version remains readable/savable but cannot be analyzed or
interpretively edited. The existing generic source route remains available.

### Add a published Digitizer observation

Use **Sources → Add Digitizer source…** for an actual Dataset published by the
unchanged Curve Digitizer. This is an optional preparation route. Opening the
Replicate Viewer or discovering declared capabilities does not activate Digitizer.
Choosing the route can activate its public producer APIs. No image is redigitized
and no study is analyzed merely by preparing a source.

Choose the published Dataset, then its actual curve/measurement pair. Choices
show opaque curve and measurement IDs as well as labels; labels alone are not
identities. Discovery reads finite 256-row pages. Counts and first-observed labels
belong to that page, not a complete curve. Previous/Next retain the current choice
as an explicitly unobserved placeholder when it is outside the page. Only actual
canonical source preparation can admit that choice. Every page is compared to the
first page's public Dataset identity, revision and Session token. A changed source
requires **Re-read source / explicit rebind** rather than a silent refresh.

Declare genuine physical-feature, independent-observation, original-point-set,
source-group and common-frame identities. Study calibration realization defaults
to the actual measurement ID and remains an explicit declaration associated with
that measurement, not a new row selector or independence certificate. Multiple
calibrations of one point set share observation and point-set identities. They are
calibration sensitivity, not independent repeats. A different curve, Dataset or
changed source clears observation declarations for review. Matching units do not
establish a common physical frame.

Press **Prepare selected source**, review the qualified original-row receipt and
uncertainty summary, then **Add prepared observation** or **Accept prepared edit /
rebind**. Preparation uses the canonical Curve Source and Graph predicate owners;
it preserves original Dataset row identity and point order. Accept requires the
study's common frame and unchanged choices/recipe. Cancel never adopts a recipe.
Known Digitizer bindings open this same dedicated route for Edit. Unchanged input
can keep the exact original representation only after current-owner validation;
source freshness is checked again on acceptance.

Explicit rebind replaces provider curve/calibration predicates. The current GUI
refuses a rebind with additional generic predicates until their replacement is
explicitly reviewed through the public preparation API. It also refuses unknown
source-dependent extensions on rebind; none are silently discarded. Same-binding
edits preserve extensions. Bound interpretive edits require the latest History
checkpoint; return there first instead of implicitly branching while a source
confirmation is open. Older/unsupported bindings remain preserved for save/open
and generic no-op, with interpretation refused.

Before Analyze, after scientific preflight, during accepted edits and result
adoption/publication, known durable bindings are revalidated against current public
producer, Dataset and full canonical source descriptors. A stale source is refused
rather than silently receiving a new revision stamp. These Viewer checks are not
an atomic lock over external Dataset writers; existing scientific service/worker
snapshot checks remain authoritative. A Job rejected after submission retains its
Job identity and requests cancellation. Status failures have bounded retries;
Cancel retries cancellation/status. Failure to confirm terminal state remains an
explicit unresolved Job state, never an adopted scientific result.

Uncertainty summaries concern the whole published Dataset, not a covariance
mapping sliced into the selected pair. Missing, unsupported, refused, changed or
unverified source integrity is reported honestly. Calibration identities describe
recorded provenance; they do not certify current image bytes. StrokeWidth is not
sigma, missing uncertainty is not zero, and no automatic weights or shared-factor
covariance estimator are introduced.

The additive APIs are specified in
[DIGITIZER_INTEROPERABILITY_API_v1.md](DIGITIZER_INTEROPERABILITY_API_v1.md).
This maintenance candidate has lexical/package authoring evidence only. Actual
original/candidate GUI workflows, keyboard/mouse parity, responsiveness, managed
scientific results and installed behavior require MAIN's separate real validation.
No migration, numerical or performance completion is claimed.
