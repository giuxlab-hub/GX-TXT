# Accepted fit to Curve Workbench

Select one accepted fit and use **Results → Transfer selected model to Workbench…**. The new named Workspace opens with an explicit representation in
the curve label. The original fit and Dataset remain unchanged. Python and
Octave use the same operation without opening a window:

```python
receipt = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'result_workbench',
                         [reference, 'Retained model geometry'])
```

```octave
receipt = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'result_workbench', ...
                         {reference, 'Retained model geometry'});
```

The Tcl entry is `::GX::DatasetCurveFit::resultWorkbench reference name`.
Names are create-only and unique; existing Workspaces are never overwritten.
The receipt `gxtxt.fit_workbench_receipt.v1` contains Workspace/curve identity,
representation, reason, original model parameter domain, independent X/Y units,
source reference, `independent_resources=true` and `fit_performed=false`.

| Saved model | Workbench representation |
|---|---|
| Linear or scalar polynomial of degree at most three | Exact line or cubic Bézier |
| Quadratic/cubic Bézier, parametric polynomial of degree at most three | Exact cubic Bézier in the physical coordinate frame |
| PCHIP, smoothing spline, open/closed parametric spline | Exact cubic Bézier chain, at most 256 spans in the requested domain |
| Circular arc within one turn | Exact retained arc, including signed sweep |
| Higher degree polynomial, Fourier, nonlinear/declared formula, component/regional/registered callback or radial mapping | Explicit sampled approximation |
| A piecewise model requiring more than 256 spans | Explicit sampled approximation with the Native2D limit recorded |

Numeric owns conversion of known polynomial spans using their analytic endpoint
values and tangents. This identity preserves the complete polynomial on each
span; it is not a fitted interpolation of arbitrary functions. For a composite
with N spans, Native2D parameter `t=(i+u)/N` corresponds to original parameter
`q=breaks[i]+u*(breaks[i+1]-breaks[i])`. Parameter breaks and the original domain
remain in conversion provenance. Scalar X(Y) and translated frames preserve
physical coordinates. Unlike X/Y units remain independent; they are never
silently replaced with a common geometric length unit.

A fallback contains at most 257 uniformly indexed rows of the already accepted
output, including both endpoints. Its provenance records every chosen output
row, the original count and `error_bound=unavailable`. It makes no approximation
tolerance or uncertainty claim. The original complete accepted output and
authoritative analytic/callback state remain in the separate scientific archive.
Malformed or unavailable retained models raise an error; a corrupt model is not
silently classified as a valid approximation.

`gxtxt.fitter_workbench_transfer.v1` carries the Native definition, conversion
receipt, full accepted source record and units. The Workbench payload owner
`importFitGeometry name transfer` validates the definition with canonical
Native2D, creates its ordinary Workspace and copies nested resources through
CORE `managedResourceCopyTree`. `gxtxt.retained_fit_archive.v1` stores the
immutable source snapshot separately from editable geometry. Copying and portable
export/import preserve exact resource bytes and CORE statistical interpretation.
The source reference is historical identity; the archive does not depend on the
source Workspace remaining present. Editing geometry never updates the imported
scientific model or presents its original uncertainty as uncertainty of an edit.

The low-level Workbench entry is a provider payload adapter. Both scripting
languages expose the complete user operation through `result_workbench`, plus
Numeric `model_geometry` for reusable exact geometry conversion and CORE
Workspace operations for inspection, validation and portable packaging.

The conversion domain is the captured output interval. For historical fits with
no retained training-domain receipt, `training_domain_status` remains
`unavailable_not_recorded`; geometry conversion does not fabricate an inference
domain or confidence claim. The original accepted model is not refitted.
