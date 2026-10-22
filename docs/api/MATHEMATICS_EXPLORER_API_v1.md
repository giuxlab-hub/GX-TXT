# Mathematics Explorer API v1

SPDX-License-Identifier: GPL-3.0-or-later

Module `viewer.mathematics_explorer` declares version1, entrypoint
`api/mathematics_explorer_api_v1.tcl`, namespace `::GX::MathematicsExplorer`.
It loads module-owned expression/state adapters and optional native UI, while
all numerical evaluation/calculus uses public math.numeric. Formula parsing is
data grammar, never Tcl eval or a replacement numerical engine.

## Exact host signatures

All arguments below are required except open's optional context. Non-underscore
module helpers are listed so their real shape is clear; this does not create a
generic Script/SDK registration or supersede their public CORE delegates.

| Signature in `::GX::MathematicsExplorer` | Result/effect |
|---|---|
| `finiteNumber value label` | finite Tcl double or labelled error |
| `tokenize expression` | controlled token list ending with end token |
| `parseExpression source` | inert constant/symbol/function/unary/binary AST |
| `initialState` | schema1 initial state dict described below |
| `presets` | name→formula dict Sine/Polynomial/Decay/Gaussian/Linear/Custom |
| `validateState state` | validated state, supplying absent symbol_units/output_unit/view_axes defaults |
| `activateNumerics` | activates actual NUMERIC_API_v1, checks required capabilities/configured Octave; no numeric result contract |
| `evaluateExpression expression x parameters units outputUnit` | public Numeric expression_evaluate result, including values/unit; x list, parameter dict, symbol-unit dict and requested output-unit string |
| `analyzeFirst state mode` | Numeric expression_analyze result; modes roots/intersections/extrema; no new facade result schema |
| `calculate state` | dict x, series, outputs, output_units; sampled function/optional derivative arrays |
| `integralOfFirst result` | finite scalar from public Numeric integration of result.x/result.outputs.f1 |
| `nativeModel state computed` | renderer model dict title/panels/native_presentation for computed samples |
| `renderPreview state computed directory` | existing Plot v4 renderTransientCurves2D result; writes preview to explicit directory |
| `sessionToken` | current Session's Interactive Document token; requires Session |
| `saveDocument state currentId sessionToken` | existing Document ID, creates when currentId empty or updates same owner |
| `readDocument id sessionToken` | validated saved state, strict owner/format/token checks |
| `listDocuments` | existing Interactive Document list for this provider |
| `publishComputed state computed documentId sessionToken outputId` | actual Dataset Publication Finalize receipt |
| `publishGraph state computed documentId token datasetId` | first publishes Dataset, then retained Plot v4 reference; graph-phase error explicitly preserves committed Dataset |
| `open ?context?` | Tcl dict default `{}`; Tk path .gx_mathematics_explorer |
| `viewerDispatch action scene` | open/rerender only; context from scene.open_context or `{}`; returns open result |

Normal GUI route is `::GX::viewerOpen viewer.mathematics_explorer
mathematics_explorer`. A current Session token is required. Existing window in
the same Session is raised before processing another context; a foreign-Session
window errors and must be closed. Supported first-open context `document_id`
restores that exact saved Document or destroys the new window on restore failure.
It is not a Workspace-ID/file-path selector. GUI scheduling/calculation/poll/
publication callbacks remain internal UI integration.

## State, expression limits and units

Initial state: schema1, title Mathematics Explorer, xmin-6/xmax6, samples301,
parameters a1/b1/c0, symbol_units x/a/b/c=`1`, output_unit1, empty view_axes,
derivative0 and exactly three stable slots f1/f2/f3. Each slot contains
id/label/preset/enabled/expression; initially only f1 enabled. validateState
requires finite increasing domain and parameters, samples integer32..1201,
derivative/enabled flags0/1, at least one enabled function, stable slot IDs and
valid preset/grammar even for inactive slots. Derivative requires f1 enabled.
Title is at most100 characters, label72, neither allows CR/LF/tab.

Grammar accepts finite numeric literals, x/a/b/c/pi, unary plus/minus and binary
`+`, `-`, `*`, `/`, `^`, parentheses and single-argument
sin/cos/tan/exp/log/log10/sqrt/abs.
Expressions are at most180 characters,55 tokens,32 AST nodes, nesting bounded
by the parser's24-depth guard. Power associates right; unary minus has the
conventional `-x^2 = -(x^2)` precedence. The grammar accepts no Tcl commands,
arbitrary functions or script evaluation.

Explicit symbol/output unit IDs are checked through the existing Unit Registry
and Numeric expression owner; use1 for dimensionless. Defaults do not establish
physical meaning. calculate uses a public uniform grid, accepts a scalar formula
result broadcast over the grid or an exact-length vector, and obtains optional
f1 differentiation from Numeric. Returned series have id/label/values/unit;
outputs maps x/enabled function IDs/optional f1_derivative to lists; output_units
maps those IDs to actual units. Derivative units/scaling use public Unit Registry
division. integralOfFirst returns a scalar only: callers must retain the
product-of-axis/function unit context; that helper does not return a unit receipt.
Numerical calculus is grid-dependent, not symbolic proof or measured uncertainty.
analyzeFirst requires f1; intersections additionally require f2 enabled and uses
the same explicit interval/parameters/units through Numeric's own contract.

## Persistence, publication and trust boundaries

Documents use owner viewer.mathematics_explorer/provider mathematics_explorer,
format gxtxt.mathematics_explorer.state/version1. Save checks Session token and
the existing Document's owner; Read and publication additionally check format/
version. These checks do not authorize arbitrary foreign-document writes.
Publication additionally
requires saved Document state matching the caller's validated current model,
expected output IDs, exact sample lengths and finite values. The adapter does
not independently recompute a caller-supplied computed result to prove formula
identity: trusted callers must use the actual same-state calculate result.

Canonical output is table.generic/CSV with float64 Variables on extendible row,
x as coordinate and actual output_units for functions/derivative, retaining
formula/Document/model provenance. Graph publication is a second explicit owner
phase; no cross-owner atomicity is claimed. Preview/transient native model is
separate from canonical Dataset/Graph publication. No private Registry/solver is
authorized by these helpers.

## Errors, languages and example

Invalid grammar/state/unit/domain, unavailable Numeric/Octave/capability,
unexpected Numeric result length/field, stale token, wrong owner/format,
unsaved/different model or invalid publication data propagate actual errors.
No generic numerical result/uncertainty guarantee or independent scientific
acceptance is added. Native helper/source examples below are source-backed,
not newly executed tests.

```tcl
::GX::modulePublicApiActivate viewer.mathematics_explorer MATHEMATICS_EXPLORER_API_v1
set state [::GX::MathematicsExplorer::initialState]
set checked [::GX::MathematicsExplorer::validateState $state]
```

This family has no registered Python/Octave Script Bridge or typed C++ SDK
method. Underlying NUMERIC_API_v1/Plot/Publication grants are distinct; no generic
C++ invoke exists. Consult the installed docs/USER_GUIDE.md,
[Numeric operation catalog](NUMERIC_EXPRESSION_OPERATIONS.md),
[Interactive Document](INTERACTIVE_DOCUMENT_API_v1.md),
[Plot v4](PLOT_DATASET_API_v4.md) and
[Dataset Publication](DATASET_PUBLICATION_API_v2.md) for their real contracts.
