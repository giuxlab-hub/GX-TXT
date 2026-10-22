# CURVE_DIGITIZER_COMPANION_API_v1

Version 1, provider `viewer.curve_digitizer`, namespace
`::GX::CurveDigitizerCompanion`, entrypoint
`api/curve_digitizer_companion_api_v1.tcl`. Trusted Tcl consumers discover owned
configuration Documents, inspect source/curve context and explicitly append
reviewed raster points. Its additive statistical consumers use existing public
Numeric, Statistical Semantics, managed resources and canonical publication.

## Complete public methods

| Exact namespaced signature | Return / effect |
|---|---|
| `sessionToken` | Current Interactive Document Session lifetime token |
| `configurationList` | List of owned configuration summaries; no GUI is opened |
| `configurationRead documentId` | document_id/document_sha256, decoded configuration context, original UTF-8 payload |
| `curveContext documentId curveId` | Configuration/source/axes/calibration plus chosen stable curve fields and Document ID/SHA |
| `sourceResolve documentId` | Verified source Dataset ID/path/SHA, contract/media_type and best-effort metadata; trusted host path, not a Script path grant |
| `commitPixelPoints documentId curveId expectedDocumentSha sessionToken pointsText` | Updates selected curve in owned Document; returns new document_id/document_sha256 and curve_id |
| `validateUncertaintyBinding binding` | Validated retained digitization statistical meaning, or error |
| `publicationUncertainty dataset` | Empty if no binding; otherwise binding/meaning/source_identity after actual payload/Variable/unit checks |
| `publishCovariance dataset target axis` | Publishes explicit response-only NxN covariance through Numeric/managed resource/Publication owners; returns canonical receipt |
| `covariancePublication dataset` | Empty if no covariance binding; otherwise checked retained covariance binding |

The last four are loaded from curve_digitizer_core_consumers.tcl by the same
entrypoint. No direct Script registration for this family or typed C++ method
exists at this checkpoint. Other uncertainty Script operations may call these
trusted host consumers internally; they remain their own declared contracts.
Underscore helpers and subprocess protocols are not additional API operations.

## Configuration, source and context identity

Every configuration access requires the current Session and a Document owned
by module viewer.curve_digitizer/provider curve_digitizer, with format
gxtxt.curve_digitizer.configuration/version 1.0. configurationList returns
document_id/SHA, configuration_id/name, source_dataset_id/SHA and calibration_ready.
configurationRead also returns the original JSON payload. curveContext requires
a nonempty existing stable curve ID; its decoded fields include configuration
and source identity, calibration_ready, axes_json/calibration_json, curve_id/name,
curve_point_count and curve_json. These JSON strings remain inert producer data.

Inspection and point append use installed python/companion_bridge.py through
python3/python on PATH, not the Viewer launcher's configurable runtime resolver.
Temporary UTF-8 files are cleaned in finally. The bridge checks JSON format/
version/configuration_id and constructs the existing Digitizer Project model.
No numerical engine or calibration algorithm is reimplemented by the consumer.

sourceResolve requires an actual image.raster contract or image/* media type,
resolves the current canonical Session resource, and compares measured SHA to
the registry SHA and nonempty captured source SHA. Source mismatch is STALE
SOURCE. Missing optional metadata is returned empty after a caught metadata-read
failure; that catch does not weaken the payload SHA checks. The returned path
is an actual trusted Tcl host result; no generic restricted client access to
private Session paths is implied.

## Explicit point commit

Capture sessionToken and document_sha256 when loading context. Commit requires
that same Session lifetime, exact nonempty expected Document SHA, existing
selected curve, complete valid calibration and verified source bytes. pointsText
is UTF-8 lines `x<TAB>y` or `id<TAB>x<TAB>y`; blank lines are ignored. Missing/
blank IDs receive UUIDs. IDs must be unique against every existing point and
other proposed points. At least one point is required. The producer converts
pixel coordinates through its actual calibration; invalid/untransformable or
nonfinite serialized results reject. No independent scientific-unit input is
accepted in place of raster pixels.

The subprocess appends points to the selected curve and preserves unrelated
JSON data semantically; the host writes the resulting payload with normal
Interactive Document Update. It returns the new SHA so callers can refresh
their optimistic token. There is no whole-process compare-and-swap guarantee:
the explicit SHA/source checks happen before the subprocess and are not repeated
as an expected-SHA argument to the final update. Do not describe this as an
atomic concurrency check spanning external processing. No fixed point-text/
configuration-byte limit is declared in this adapter. Canonical scientific
Dataset publication is a separate explicit action; this commit edits a Document.

## Retained statistical identity

validateUncertaintyBinding requires schema gxtxt.digitizer_publication_binding.v1,
64-lowercase-hex payload_sha256, point_count 1–4096 and managed resources for
configuration/points/state/values/interpretation. The interpretation resource is
at most 1MiB, correct format, valid Statistical Semantics, correct point count,
configuration/point SHA references and exactly 40*N value bytes. Stable x/y,
sigma_x/y and point-ID Variable identities must be nonempty. This validates
the retained binding; by itself it does not look up a current canonical Dataset.

publicationUncertainty additionally compares dataset_id and current source
payload identity; X/Y/sigma Variables must be enabled/rank-one with exact
separate X/Y units. covariance_xy must be enabled/rank-one with the same physical
X*Y unit string as the reviewed metadata. It returns binding, retained meaning
and source_identity. Unknown uncertainty is not converted to zero.

publishCovariance requires axis x/y and a real reviewed binding, at most 512
original points, an allowed full_response_covariance fit plan with orientation
x_of_y/y_of_x, and Unit Registry confirmation of squared response units. It
reads the retained Numeric state in 64KiB chunks (at most 8MiB, correct format/
state SHA), invokes public Numeric digitization_covariance, checks returned state
identity/count and revalidates the source capture. It validates NxN shape and
writes column-major float64 little-endian managed bytes, then publishes an HDF5
Variable `covariance` with dimensions source_row/source_column and unit U*U.
Predictor uncertainty is explicitly excluded; this is not full errors-in-
variables inference. Binding records original source, axis, resource, fit plan
and actual covariance Dataset identity.

covariancePublication validates that retained binding/meaning/resource/current
covariance Dataset identity and fit-plan interpretation still agree. It does not
independently recompute the matrix or rerun publicationUncertainty against a
possibly changed original source Dataset. Final metadata association occurs
after canonical publication, so a later metadata failure is not proof the
Dataset was never committed; use the canonical receipt/registry to reconcile.

The loaded shared host helper
`::GX::CurveDigitizerNumericCore::covarianceUnit xUnit yUnit` constructs the exact
X*Y unit string: two explicit trimmed symbols, each at most 128 characters;
simple atomic symbols join with `*`, compound symbols are parenthesized. It
does not independently validate dimensional conversion. It is a reused host
adapter, not an additional Script/C++ family or scientific solver.

## Source-backed inspection example and failures

```tcl
set token [::GX::CurveDigitizerCompanion::sessionToken]
set configurations [::GX::CurveDigitizerCompanion::configurationList]
if {[llength $configurations]} {
    set id [dict get [lindex $configurations 0] document_id]
    set saved [::GX::CurveDigitizerCompanion::configurationRead $id]
    set verifiedSource [::GX::CurveDigitizerCompanion::sourceResolve $id]
}
```

Unexecuted source-backed example; requires an actual compatible Session/Document.
Wrong owner/format/lifetime/SHA, missing curve/source, Python/model errors,
malformed point text, stale payload/Variable meanings, unsupported uncertainty
plan/unit/resource/shape or publication errors propagate. There is no blanket
GUI catch-to-success, new solver, raw canonical writer or generic C++ invoke.
Installed/native/scientific and all broader release acceptance remain separate.
