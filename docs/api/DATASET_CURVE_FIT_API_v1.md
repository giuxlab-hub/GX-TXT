# Dataset Curve Fit API v1

`sampleDescriptor sample_id` returns a dictionary containing `sample_id`, `title`,
`description`, `axes` (X/Y Variable IDs, labels, units, semantic roles and value
kinds), `generator_id`, `generator_version`, `producer_module`, `producer_version`,
deterministic `generator_parameters`, and `expected_result` with a named metric
and tolerance. `sampleCatalog` retains the compatible ID-to-title mapping.

`publishFitDataset key requested_id` and `publishSampleDataset sample_id requested_id`
use the exact validated nonempty public ID supplied by the caller. They perform
normal create-only collision checking through Dataset Publication v2. Invalid IDs
are rejected, never sanitized/generated. Full schema and structured metadata are
part of the publication transaction. Samples and accepted local CORE curves do
not enter the Dataset Registry until an explicit publication call.

Built-in provenance is `source_kind=builtin_sample`, `source_sample_id` and the
complete descriptor; `source_dataset_id` is absent. Real Dataset sources retain
Dataset ID, fingerprint, variables and filters. The CSV header uses the applicable
source identity column, and its sidecar preserves this lineage. Legacy dev-051
saved `source_kind=sample` documents remain readable and their accepted sample
curve provenance is upgraded when restored.

Provider `viewer.dataset_curve_fit` 0.3.0, GX-TXT dev-052. Activate through `::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1`. The existing Tk viewer and public host API share canonical Dataset reads, Native2D CORE curves, Numerical API calculations and Interactive Document persistence. Viewer UI lifecycle stays host-only.

```tcl
set key [::GX::DatasetCurveFit::new]
::GX::DatasetCurveFit::loadSample $key circular_arc
set fit [::GX::DatasetCurveFit::preview $key circular_arc all {parameter 0 1 1000} 2 {} {}]
set coreId [::GX::DatasetCurveFit::accept $key]
# Only an explicit publication creates a Session Dataset.
set published [::GX::DatasetCurveFit::publishFitDataset $key "circular_arc_result"]
::GX::DatasetCurveFit::exportCsv $key /host/chosen/result.csv
::GX::DatasetCurveFit::close $key
```

`loadSource key dataset_id x_variable_id y_variable_id filters` reads a filtered canonical source with stable identities. `loadSample key sample_id` uses an internal source; `sampleCatalog` lists local samples. Samples are not added to Dataset Registry by loading or fitting. `publishSampleDataset sample_id name` explicitly creates a Dataset. `preview key model scope domain degree initial options` returns fitted/residual samples, training/source metrics, source/selection identity, grid kind/count and reconstructible `model_state_json`. Scope is `all` or `selected`; point selection uses the existing public Native2D API.

Legacy models remain linear, polynomial, exponential, power_law and gaussian. New models are circular_arc, quadratic_bezier, cubic_bezier, pchip, smoothing_spline and fourier. Domain remains `source` or `{min max samples}` for function models; parametric arc/Bézier use `{parameter t_min t_max samples}` within `[0,1]`. Existing 2–10000 output bounds are preserved. Fourier degree is harmonic order, with optional positive `period`; it requires at least `2N+1` independent samples and a full-rank design. No low order cap is introduced. Smoothing uses nonnegative `smoothing_lambda`: zero interpolates, larger values penalize curvature. See [Numerical API](../../plugins/modules/math.numeric/NUMERIC_API_v1.md) for reconstruction/projection and conventions.

`accept` creates a separate CORE curve, without Dataset publication. Accepted records persist model state, points, grid/options, selected source points/filters/hash, residual convention and metrics through the GUI's Interactive Document lifecycle. `publishFitDataset` explicitly writes fitted X/Y and complete namespaced model/provenance metadata through Dataset Publication v2. CSV export writes the accepted curve and `<csv>.metadata.ini` with model/provenance and CSV SHA. A stale source/selection or duplicate acceptance is rejected. Sample, source Dataset, CORE fit and published Dataset identities remain distinct.

See [viewer manual](../../plugins/modules/viewer.dataset_curve_fit/MANUAL.md), [publication](DATASET_PUBLICATION_API_v2.md) and [Canonical Dataset API](CANONICAL_DATASET_API_v2.md). Numeric model operations are separately callable by both Script Bridge languages; this does not expose arbitrary host file destinations through the viewer API.

## Exact source science in dev-052

The additive GUI workspace retains per-source descriptors and accepted model/resource identity. Exact filtered/selected input streams independently of display extrema. Orientation X=f(Y) swaps mathematical dependent/independent bindings while retaining physical output X/Y; R=f(theta) records shared polar frame and native/Numerical conventions. Ordered parametric polynomial/natural/periodic cubic supports row/path/user parameterization and explicit topology. No accepted curve is refitted on restore. Shared model APIs provide bounded exact projection/residual pages and model-owned resource lifetime. The manual describes batch acceptance, source reversal, source removal and explicit publication of historical accepted results.
