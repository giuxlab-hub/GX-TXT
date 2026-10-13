# demo.numeric.smoothing — Complete User and Scientific Manual

Plugin ID: `demo.numeric.smoothing`  
Plugin version: `1.0.2`  
Framework: current GX-TXT public scientific APIs  
Package type: external independently installable analysis plugin  
License: GNU GPL v3 or later

This manual describes the complete reproducible GX-TXT workflow for the
numerical smoothing demonstration. It documents the actual public interfaces and
GUI labels correspond to the documented module configuration.

## 1. Module overview

`demo.numeric.smoothing` demonstrates the smoothing operations actually exposed
by the public `math.numeric` `NUMERIC_API_v1` service in GX-TXT 0.9.7.72.

The module exercises these public smoothing methods:

- `moving_mean`;
- `moving_median`;
- `savitzky_golay`;
- `local_polynomial`.

The module is intended as both a scientific tutorial and a reference external
plugin. It reads a normal canonical Dataset through Analysis Source, resolves
stable Dataset variable identities, calls the public numerical service, publishes
one derived comparison Dataset through Dataset Publication API v2, and renders
four automatic module-owned graphs through Graph Provider API v1 and the shared
GX-TXT graphics infrastructure.

The scientific purpose is not to declare one smoothing method universally
superior. The demonstration shows how different methods suppress noise, respond
to isolated measurement disturbances, preserve local curvature, and handle
Dataset boundaries.

The complete canonical demonstration flow is:

```text
GX-TXT Numerical Examples
        ↓
Smoothing Session Generator
        ↓
normal independent GX-TXT Session
        ↓
raw/smoothing_demo.csv + metadata/ground_truth.txt
        ↓
normal Acquisition import
        ↓
canonical source Dataset
        ↓
Analysis Source + stable variable bindings
        ↓
NUMERIC_API_v1 dataset_smooth
        ├─ moving_mean
        ├─ moving_median
        ├─ savitzky_golay
        └─ local_polynomial
        ↓
reference-error diagnostics
        ↓
Dataset Publication API v2
        ↓
derived comparison Dataset
        ↓
automatic Graph Provider outputs
        ↓
PNG graphs + cache-only rerender
        ↓
optional additional plot.dataset graphs
```

## 2. Required GX-TXT version

The development and reference baseline is:

```text
GX-TXT 0.9.7.72
```

The package manifest declares:

```text
framework_min=0.9.7.72
```

The plugin remains external. Installing it must not modify, repackage or create a
new GX-TXT framework release.

The protected CORE dependency is:

```text
math.numeric
```

with public API:

```text
NUMERIC_API_v1
```

GX-TXT 0.9.7.72 advertises the smoothing capabilities used by this plugin:

```text
smoothing
moving_average
moving_median
savitzky_golay
local_polynomial_smoothing
dataset_smoothing
grid_analysis
```

## 3. Corresponding Session Generator

GX-TXT 0.9.7.72 does not ship a built-in `Smoothing` generator, so this release
provides a **portable external Session Generator API v1 package** specifically
for this demo. It is imported into the existing numerical example library; the
framework source tree is not modified.

Canonical relationship:

```text
Library:   GX-TXT Numerical Examples
Category:  Mathematics
Generator: Smoothing
```

Stable identities:

```text
Library ID:   org.giuxlab.gxtxt.numerical_examples
Generator ID: smoothing
Generator version: 1.0.0
```

Portable generator package:

```text
gxtxt_numerical_examples_smoothing_1.0.0.zip
```

Generator package SHA-256:

```text
9c7fdeeaa4f96b13b6dea4a4bde9673bf3ed77f86b365437a0e54110f67baab7
```

The same generator ZIP is also included in the installed plugin under:

```text
session_generators/gxtxt_numerical_examples_smoothing_1.0.0.zip
```

The generator produces an ordinary independent GX-TXT Session containing:

```text
raw/smoothing_demo.csv
metadata/ground_truth.txt
metadata/session_generator.ini
```

`metadata/session_generator.ini` is written by GX-TXT after successful
generation. `metadata/ground_truth.txt` is scientific reproducibility metadata
created by the generator. The analysis plugin does not read either file
directly; after Acquisition import, it uses only the canonical Dataset and its
public metadata/bindings.

The generated CSV is byte-identical to the packaged reference example used by
the plugin tests. Its SHA-256 is:

```text
cb2ec3a7cd62cfd026be0dc31ee975479da697224978d023d9cea6a56a20ebd2
```

This preserves the intended architecture:

```text
Session Generator Library
        ↓
Smoothing generator
        ↓
normal independent GX-TXT Session
        ↓
normal Acquisition import
        ↓
canonical Dataset
        ↓
demo.numeric.smoothing
```

The generated Session does not depend on the generator package after creation.

## 4. Creating the example Session

### 4.1 Install the plugin

Install the plugin as described in Section 7. This makes an identical copy of
the portable generator package available inside the installed module. The
generator ZIP can also be imported from the separately distributed file with the
same filename.

### 4.2 Import the Smoothing generator

Use the actual GX-TXT 0.9.7.72 GUI labels:

```text
New Session
→ Generate Session...
→ Manage Libraries...
```

In `Library Manager`:

1. Select `GX-TXT Numerical Examples` under `Installed Libraries`.
2. Click `Import Generator...`.
3. Select:

```text
gxtxt_numerical_examples_smoothing_1.0.0.zip
```

If importing the copy bundled with the installed plugin, its location is:

```text
<GXTXT_ROOT>/plugins/modules/demo.numeric.smoothing/session_generators/
gxtxt_numerical_examples_smoothing_1.0.0.zip
```

`<GXTXT_ROOT>` is the user's actual GX-TXT installation directory. It is an
intentional runtime path variable.

Import validates the generator package but does not execute `generate.py`.
Execution occurs only after the user explicitly requests `Generate Session`.

After import, `Generators in Selected Library` contains:

```text
Smoothing
```

with category `Mathematics`. Click `Hide Manager` to return to the generator
browser.

### 4.3 Generate the deterministic Session

In the expanded `Session Generator Library` browser select:

```text
GX-TXT Numerical Examples
→ Mathematics
→ Smoothing
```

The generator suggests the Session name:

```text
smoothing-example
```

The user may replace it with another value. `<SESSION_NAME>` in this manual
means that user-selected name. Click:

```text
Generate Session
```

GX-TXT creates and opens the normal independent Session. The scientific files
created by the generator are:

```text
raw/smoothing_demo.csv
metadata/ground_truth.txt
```

GX-TXT also writes generator provenance to:

```text
metadata/session_generator.ini
```

### 4.4 Import the generated CSV as the source Dataset

The Session Generator creates the scientific source files but, consistently with
the existing GX-TXT numerical generators, Dataset creation remains a normal
Acquisition operation.

Open the `Acquisition` tab and use the framework-owned generic CSV batch import:

1. In `Multi-CSV canonical dataset import (v0.8.2)`, enable `Use batch table`.
2. Click `+ Add CSV`.
3. Select the generated Session file:

```text
<SESSION_ROOT>/raw/smoothing_demo.csv
```

`<SESSION_ROOT>` is the generated Session directory.
4. Set `Dataset ID` to:

```text
smoothing.source
```

5. Set `Contract` to:

```text
table.generic
```

6. Leave `Delimiter` as `auto`.
7. Set `Header` to `1`.
8. Click `Variables`.
9. Keep the three canonical variables:

```text
time_s
reference_V
measured_V
```

10. Assign the following units and semantic roles:

| Variable | Unit | Semantic role |
| --- | --- | --- |
| `time_s` | `s` | `independent` |
| `reference_V` | `V` | `reference` |
| `measured_V` | `V` | `measured` |

11. Click `Import enabled pending into current session`.

A fresh validation import produces three stable variable IDs. During development
the fresh Session assigned `v0001`, `v0002` and `v0003` in column order, but the
plugin does **not** depend on those literal IDs. It resolves the actual stable
`variable_id` values from the current Analysis Source runtime.

The generated `metadata/ground_truth.txt` is not required by the plugin. The
reference signal is already a canonical CSV column, so the plugin does not need
a private metadata-file importer.

## 5. Scientific dataset

The packaged deterministic Dataset contains 501 uniformly spaced samples:

```text
X start: 0 s
X stop:  10 s
X step:  0.02 s
Samples: 501
```

CSV columns:

```text
time_s
reference_V
measured_V
```

### 5.1 Reference signal

The clean reference signal is:

```text
reference(x) =
    0.35 sin(2π·0.22·x)
  + 0.18 cos(2π·0.55·x)
  + 0.04 x
  + 1.10 exp[-0.5 ((x-3.10)/0.22)^2]
  - 0.75 exp[-0.5 ((x-7.00)/0.35)^2]
  + 0.45 exp[-0.5 ((x-5.25)/0.60)^2]
```

The mixture contains smooth oscillatory behavior, a narrow positive feature, a
broader negative feature and a broad shoulder. It therefore exercises noise
suppression without reducing the problem to a featureless straight line.

### 5.2 Deterministic measured signal

The measured signal is:

```text
measured = reference + seeded Gaussian noise + isolated disturbances
```

The generator parameters are:

```text
random seed: 1974
Gaussian sigma: 0.11 V
```

Three isolated measurement disturbances are added at fixed sample indices:

```text
index 122: +0.65 V at x = 2.44 s
index 308: -0.70 V at x = 6.16 s
index 431: +0.55 V at x = 8.62 s
```

These are intended to represent occasional measurement spikes, not a pathological
adversarial input. They make the different behavior of mean- and median-based
smoothing visible.

The packaged CSV SHA-256 is:

```text
cb2ec3a7cd62cfd026be0dc31ee975479da697224978d023d9cea6a56a20ebd2
```

The canonical Session Generator executes its packaged `generate.py` and creates
the same CSV under `raw/smoothing_demo.csv`. The plugin also retains
`examples/generate_smoothing_demo.py` as a standalone reproducibility helper; it
implements the same deterministic scientific definition.

### 5.3 Direct reference diagnostics of the packaged input

These values are computed directly from the packaged CSV against its reference
column, before any GX-TXT smoothing method is applied:

```text
measured RMSE:               0.11898447178888386 V
measured MAE:                0.09027265784214515 V
measured maximum abs error:  0.8008427063171 V
```

They describe the deterministic input, not a smoothing result.

## 6. Mathematical background

Smoothing estimates an underlying trend or signal from observations containing
noise or local disturbances. The key tradeoff is between noise suppression and
feature preservation. A wider smoothing window usually reduces high-frequency
variation more strongly but can also broaden peaks, flatten curvature or move
local features depending on the method and endpoint treatment.

### 6.1 Moving mean

For an odd window containing nearby observations, moving mean smoothing replaces
an observation by the arithmetic mean of the available values in that local
window.

Conceptually:

```text
y_s(i) = (1/N_i) Σ y(j)
```

where `N_i` is the number of samples available in the window for sample `i`.

GX-TXT 0.9.7.72 reports the endpoint policy as:

```text
shrink
```

The window is shortened near Dataset boundaries rather than inventing samples
outside the Dataset.

Moving mean smoothing is efficient and effective for zero-mean random noise, but
an isolated large disturbance contributes directly to the local arithmetic mean.

### 6.2 Moving median

Moving median uses the median of the local window rather than its arithmetic
mean. The median is less sensitive to isolated large disturbances.

GX-TXT 0.9.7.72 also reports:

```text
endpoint_policy=shrink
```

The method can preserve step-like structures and reject spikes better than a
moving mean, but it is nonlinear and may alter fine smooth curvature differently.

### 6.3 Savitzky-Golay

Savitzky-Golay smoothing fits a local polynomial over a fixed odd window and uses
the polynomial model to produce a smoothed value. It is commonly used when local
shape and curvature should be retained better than with simple averaging.

The public v1 API requires:

- an explicit odd `window`;
- an explicit polynomial `degree`;
- `degree < window`;
- a uniform X grid;
- the GNU Octave `signal` package providing `sgolayfilt`.

GX-TXT exposes the endpoint policy as:

```text
signal.sgolayfilt
```

The plugin reports that public policy string rather than pretending that a
different endpoint rule is used.

### 6.4 Local polynomial smoothing

`local_polynomial` performs local polynomial least squares using the actual X
coordinates. It therefore remains meaningful for non-uniform coordinates in the
public numerical API, although this demo requires a uniform X grid because it
also runs Savitzky-Golay in the same comparison.

GX-TXT 0.9.7.72 reports:

```text
endpoint_policy=shift_full_window
```

Near a boundary, the full local window is shifted inward instead of being
shortened.

### 6.5 Why the methods are not ranked

The plugin reports RMSE, MAE, maximum absolute error, endpoint RMSE and interior
RMSE for each configured method. These quantities are specific to this Dataset
and parameter selection. A different scientific signal can favor a different
tradeoff, so the module does not produce a best-method score or ranking.

## 7. Plugin installation

The release package is:

```text
demo.numeric.smoothing_1.0.1.zip
```

Install through the actual GX-TXT GUI workflow:

```text
Modules
→ Install plugin...
→ select demo.numeric.smoothing_1.0.1.zip
```

After installation, remain in `Modules` and locate:

```text
Numerical Smoothing Demo
```

Stable plugin/module ID:

```text
demo.numeric.smoothing
```

Enable the module with the normal `Enable` action.

The package contains a declarative `plugin-package.ini` and uses Plugin Install
API v1. No framework source modification or custom installer is required.

## 8. Running the plugin

Open the Session containing the imported `smoothing.source` Dataset.

### 8.1 Configure the analysis

1. In `Modules`, enable `Numerical Smoothing Demo`.
2. Open the `Analysis` tab.
3. In the module frame
   `Numerical Smoothing Demo (demo.numeric.smoothing)`, enable
   `Run / recalculate now`.
4. In `Calculation configuration`, use the default demonstration values unless
   deliberately testing another parameter set:

```text
Output Dataset ID:                 demo.numeric.smoothing.result
Moving mean window (odd samples): 15
Moving median window (odd samples): 15
Savitzky-Golay window (odd samples): 15
Savitzky-Golay polynomial degree: 3
Local-polynomial window (odd samples): 15
Local-polynomial degree: 2
```

5. In `Dataset sources (Analysis Source Map API v1)`, set source `primary` to:

```text
smoothing.source
```

6. In `Input variable bindings`, bind:

```text
Independent X variable        → primary.time_s
Measured / noisy Y variable   → primary.measured_V
Reference / clean Y variable  → primary.reference_V
```

The GUI display names may include Dataset/source context. The module resolves the
selection to the stable Dataset `variable_id` values exported by GX-TXT.

7. Run:

```text
PHASE 2 - RUN SELECTED ANALYSES
```

### 8.2 Parameter validation

The plugin rejects invalid combinations explicitly before publication:

- every smoothing window must be an odd integer of at least 3 samples;
- no configured window may exceed the current Dataset length;
- Savitzky-Golay degree must be a non-negative integer smaller than its window;
- local-polynomial degree must be a non-negative integer smaller than its
  window;
- X must be strictly increasing;
- the combined four-method demo requires a uniform X grid because
  Savitzky-Golay requires one;
- measured and reference variables may not be the same stable variable;
- non-empty measured/reference units must agree;
- the output Dataset ID must differ from the source Dataset ID.

## 9. Numerical processing chain

The implemented public-API chain is:

```text
smoothing.source
→ Analysis Source Map API v1 runtime
→ stable Dataset variable_id resolution
→ Table Stream API v3
→ NUMERIC_API_v1 dataset_grid_info
→ NUMERIC_API_v1 dataset_smooth
     moving_mean
     moving_median
     savitzky_golay
     local_polynomial
→ structural/API validation
→ reference-error diagnostics
→ Dataset Publication API v2
→ demo.numeric.smoothing.result
→ Graph Provider API v1
→ shared GX-TXT graphics helpers
→ four PNG artifacts
```

No private interpolation/smoothing/filter implementation is included in the
plugin. In particular, the plugin does not call `sgolayfilt`, `movmean` or a
private moving-window routine directly. The numerical operation is delegated to
`NUMERIC_API_v1`.

Dataset publication begins only after the numerical/API checks pass. Therefore a
failed smoothing calculation does not intentionally leave a newly published
derived Dataset behind.

## 10. Expected numerical result and validation

### 10.1 Structural checks

For each public smoothing result the module verifies:

- output length equals source length;
- returned X length equals source length;
- returned X remains associated with the source coordinates;
- maximum X displacement is below the runtime tolerance;
- smoothed values are finite;
- the API returns the requested method identity;
- the API reports the configured window;
- polynomial degree is honored where applicable;
- an endpoint policy is explicitly reported.

The X-association tolerance is computed as:

```text
64 × machine_epsilon × max(1, max(abs(X)))
```

This is a floating-point identity tolerance, not a smoothing-quality tolerance.
For the public v1 methods X is expected to be preserved rather than resampled.

### 10.2 Error diagnostics

For measured data and each smoothing method, error relative to the bound clean
reference is:

```text
error_i = smoothed_i - reference_i
```

The module reports:

```text
RMSE = sqrt(mean(error^2))
MAE  = mean(abs(error))
maximum absolute error = max(abs(error))
```

For each smoother it also reports endpoint and interior RMSE. The edge region is
half the configured window width at each end:

```text
edge_count = (window - 1) / 2
```

This makes endpoint behavior visible rather than hiding it inside a single whole-
record metric.

The plugin does **not** impose a universal numerical pass threshold saying that
one method must outperform another. For the packaged deterministic demonstration,
the integration test additionally checks that each default smoothing method
reduces whole-record RMSE relative to the packaged noisy measurement. That is a
property of this canonical example, not a general theorem about smoothing.

## 11. Output Dataset

Default Dataset ID:

```text
demo.numeric.smoothing.result
```

Contract:

```text
table.generic
```

Published variables:

| Variable | Meaning |
| --- | --- |
| `x` | source independent variable |
| `reference` | clean/reference signal |
| `measured` | measured/noisy signal |
| `smooth_moving_mean` | moving-mean result |
| `error_moving_mean` | moving-mean minus reference |
| `smooth_moving_median` | moving-median result |
| `error_moving_median` | moving-median minus reference |
| `smooth_savitzky_golay` | Savitzky-Golay result |
| `error_savitzky_golay` | Savitzky-Golay minus reference |
| `smooth_local_polynomial` | local-polynomial result |
| `error_local_polynomial` | local-polynomial minus reference |

The output preserves the source X unit and Y units. Smoothed and error variables
use the measured-Y unit; the reference variable preserves the bound reference
unit.

Publication provenance records:

- source Dataset ID;
- source X variable ID;
- source measured-Y variable ID;
- source reference-Y variable ID;
- plugin version;
- `NUMERIC_API_v1` use;
- all configured smoothing windows and polynomial degrees.

The published Dataset remains a normal canonical Dataset and can be reopened by
`plot.dataset` or other compatible GX-TXT modules.

## 12. Automatic graphs

Automatic graphs are a required part of this plugin. With the default graph
selection, a successful Run produces four PNG files immediately.

### 12.1 Measured and reference signal

Graph ID:

```text
demo.numeric.smoothing.original
```

Artifact:

```text
01_measured_and_reference.png
```

Series:

- measured/noisy observations;
- clean/reference signal.

Purpose: show the magnitude and structure of the original noise/disturbances
before smoothing.

### 12.2 Measured signal and smoothing methods

Graph ID:

```text
demo.numeric.smoothing.methods
```

Artifact:

```text
02_measured_and_smoothing.png
```

Series:

- measured/noisy signal;
- moving mean;
- moving median;
- Savitzky-Golay;
- local polynomial.

Purpose: show noise suppression relative to the actual measurements.

### 12.3 Reference signal and smoothing methods

Graph ID:

```text
demo.numeric.smoothing.reference
```

Artifact:

```text
03_reference_and_smoothing.png
```

Series:

- clean/reference signal;
- all four smoothed signals.

The noisy measurements are deliberately omitted so local shape differences are
not visually obscured.

### 12.4 Smoothing errors

Graph ID:

```text
demo.numeric.smoothing.errors
```

Artifact:

```text
04_smoothing_errors.png
```

Series:

```text
smooth_method - reference
```

for all four methods, plus a zero-error reference line.

Purpose: make local bias, peak distortion and endpoint effects visible.

### 12.5 Axis labels and units

When graph configuration remains `auto`, X and Y labels are derived from the
actual bound source variable names and units. The plugin does not hard-code a
unit that can contradict Dataset metadata.

## 13. Interpretation

A scientifically sensible run should show all of the following:

- the measured trace visibly fluctuates around the clean reference;
- isolated measurement spikes are obvious in the first graph;
- all smoothing outputs have the same number of samples and exactly associated X
  coordinates;
- moving mean suppresses random noise but can spread the influence of a spike;
- moving median is less sensitive to isolated spike amplitude;
- Savitzky-Golay and local polynomial smoothing retain local curvature according
  to their configured polynomial/window behavior;
- boundary behavior may differ from the interior and is reported separately;
- signed error curves cross zero and reveal local bias rather than only a global
  scalar score.

A problem is indicated by:

- a different output sample count;
- non-finite output values;
- shifted X coordinates;
- an unexpected returned method/window/degree;
- missing endpoint-policy information;
- a missing derived Dataset;
- a missing automatic graph artifact;
- a numerical API or Octave package error.

## 14. Reproducibility

The packaged demonstration is reproducible because:

- the canonical Session Generator has stable ID `smoothing` and version `1.0.0`;
- generation is deterministic and was verified by generating two independent Sessions;
- the generated CSV is byte-identical to the plugin's packaged reference CSV;
- GX-TXT records generator provenance in `metadata/session_generator.ini`;
- the reference equation is explicit;
- the X grid is fixed at 501 samples from 0 to 10 s in 0.02 s steps;
- Gaussian noise uses Python `random.Random` with seed `1974`;
- noise sigma is fixed at `0.11 V`;
- the three isolated disturbances use fixed indices and amplitudes;
- the example CSV SHA-256 is fixed and documented;
- default smoothing parameters are fixed in `module.ini`;
- the module records its own installed version for provenance;
- the documented public Dataset and numerical contracts are used.

The normal reproduction path is `New Session` → `Generate Session...` →
`GX-TXT Numerical Examples` → `Mathematics` → `Smoothing`. For source-level
reproduction outside the GUI, the plugin also contains:

```text
python3 examples/generate_smoothing_demo.py
```

Both paths produce the same canonical CSV bytes.

## 15. Troubleshooting

### Plugin is not visible

Install with `Modules` → `Install plugin...`. Confirm that
`Numerical Smoothing Demo` appears in `Modules` and enable it.

### Smoothing generator is not visible

Open `New Session` → `Generate Session...` → `Manage Libraries...`, select
`GX-TXT Numerical Examples`, and use `Import Generator...` with
`gxtxt_numerical_examples_smoothing_1.0.0.zip`. Importing the package does not
execute it. After import, hide the manager and select `Mathematics` →
`Smoothing`.

If GX-TXT reports that generator ID `smoothing` already exists in the selected
library, do not import a duplicate; use the installed `Smoothing` generator.

### Wrong Session or Dataset

The canonical tutorial Dataset ID is `smoothing.source`. If another compatible
Dataset is used, it must contain a strictly increasing X variable, a measured Y
variable and a clean/reference Y variable of the same length.

### Wrong variable binding

Bind the independent, measured and reference fields in `Input variable bindings`.
The module reports a clear error if any stable variable identity is unavailable.

### Output Dataset ID equals input Dataset ID

Use a distinct output ID. The default is:

```text
demo.numeric.smoothing.result
```

The module intentionally refuses to overwrite its source Dataset.

### Even smoothing window

All public v1 smoothing windows used by this demo are centered odd windows. Use
an odd integer of at least 3 samples.

### Polynomial degree is too large

Savitzky-Golay and local-polynomial degree must be smaller than their respective
window.

### Savitzky-Golay reports a non-uniform X error

The public API requires uniform X for Savitzky-Golay. The packaged demonstration
is uniform. If a different Dataset is used, either use a uniform X Dataset or use
a different analysis specifically designed for non-uniform smoothing. This demo
runs all four methods together and therefore requires uniform X.

### Savitzky-Golay reports that `signal` / `sgolayfilt` is unavailable

GX-TXT 0.9.7.72 exposes Savitzky-Golay through `math.numeric`, which requires the
GNU Octave `signal` package. Install/fix that framework runtime dependency; the
plugin does not replace it with a private implementation.

### Automatic PNG is missing

Check the analysis log for a Graph Provider/shared-graphics error. A successful
run normally creates all enabled graph files in the module analysis directory.

### Rerender fails because `render_cache.mat` is missing

Run/recalculate the analysis once. Cache-only rerender intentionally requires the
module's `render_cache.mat` and does not recompute smoothing.

## 16. Public API usage

The plugin uses only the public GX-TXT interfaces required by its implementation:

- **Standard Module API v1 (`MODULE_API_v1`)** — external analysis-module
  descriptor and standard Octave lifecycle.
- **Analysis Source Map API v1 (`ANALYSIS_SOURCE_MAP_API_v1`)** — binds source ID
  `primary` to a canonical Dataset and transports stable variable selections.
- **Dataset Variable Schema API v3 (`DATASET_VARIABLE_SCHEMA_API_v3`)** — stable
  Dataset variable identities exposed through the runtime metadata.
- **Table Stream API v3 (`TABLE_STREAM_API_v3`)** — reads the bound X, measured
  and reference variables without accessing private Dataset files.
- **Numerical API v1 (`NUMERIC_API_v1`)** — `dataset_grid_info` and
  `dataset_smooth` for all four smoothing methods.
- **Dataset Publication API v2 (`DATASET_PUBLICATION_API_v2`)** — publishes the
  derived multivariable canonical Dataset.
- **Progress API v1 (`PROGRESS_API_v1`)** — reports preparation, numeric,
  publication and graph-render stages.
- **Graph Provider API v1 (`GRAPH_PROVIDER_API_v1`)** — declares the four
  automatic module-owned graph outputs.
- **Plot Module API v1 / `PLOT_DATASET_API_v1`** — the published Dataset remains
  usable for additional user-configured `plot.dataset` graphs and is exercised
  by the integration test.
- **Plugin Install API v1 (`PLUGIN_INSTALL_API_v1`)** — installs the independent
  plugin ZIP package.
- **Session Generator Library API v1** — used by the separately importable
  `Smoothing` Session Generator package that creates the canonical demo Session.
  The analysis module itself does not call this API at runtime.
- **Documentation API v1 (`DOCUMENTATION_API_v1`)** — exposes this manual from
  the module descriptor.

No private Dataset registry files or runtime/cache formats are used as scientific
input.

## 17. Package contents

The release structure is:

```text
demo.numeric.smoothing/
├── plugin-package.ini
├── module.ini
├── README.md
├── MANUAL.md
├── CHANGELOG.md
├── LICENSE
├── examples/
│   ├── smoothing_demo.csv
│   └── generate_smoothing_demo.py
├── session_generators/
│   ├── README.md
│   └── gxtxt_numerical_examples_smoothing_1.0.0.zip
├── runtime/
│   ├── demo_numeric_smoothing.m
│   ├── demo_numeric_smoothing_main.m
│   ├── demo_numeric_smoothing_render.m
│   ├── demo_numeric_smoothing_rerender.m
│   └── demo_numeric_smoothing_rerender_main.m
└── tests/
    ├── README.md
    ├── test_static.py
    ├── test_publication_table.tcl
    └── test_framework_integration.tcl
```

## 18. Verification workflow

Verify the module in a disposable scientific Session. The expected checks cover:

```text
plugin descriptor/package validity
Plugin Install API installation
discovery by GX-TXT 0.9.7.72
Session Generator API v1 package import
Smoothing generator discovery under GX-TXT Numerical Examples / Mathematics
two deterministic generated Sessions
generated CSV byte identity and generator provenance
generic CSV Dataset import from the generated Session
source Dataset discovery
stable variable identity
Analysis Source bindings
NUMERIC_API_v1 capability discovery
all four public Dataset smoothing methods
configured window/degree reporting
endpoint-policy reporting
X association / no shift
output length and finite-value checks
Dataset Publication API v2
published Dataset reopen
reference-error metric recomputation
four automatic Graph Provider PNG files
cache-only rerender
plot.dataset compatibility
```

Execution-dependent tests report `SKIP`, not `PASS`, when GNU Octave is not
available in the validation environment.

## 19. Known limitations

- The combined comparison requires a uniform X grid because the public
  Savitzky-Golay operation requires uniform X.
- The plugin requires a bound reference variable to compute objective error
  diagnostics; it is a demonstration/reference module rather than a generic
  blind smoothing front end.
- No smoothing spline is demonstrated because GX-TXT 0.9.7.72
  `NUMERIC_API_v1` explicitly does not provide a v1 smoothing-spline method.
- The plugin does not design digital filters and does not call the separate
  `digital_filter` operation; that is outside this smoothing demo.
- Graph rerender uses `render_cache.mat` and does not rerun numerical smoothing.
- GX-TXT 0.9.7.72 does not ship `Smoothing` in its built-in generator library;
  this release supplies it as a portable individual generator package. Importing
  it modifies only the user's installed Session Generator Library data, not the
  GX-TXT framework source tree.
- The generated Session initially contains RAW scientific data and ground-truth
  metadata; the canonical Dataset is created afterward through the normal
  Acquisition workflow, matching the behavior of the existing numerical example
  generators.
- The plugin does not automatically import `metadata/ground_truth.txt`; objective
  validation uses the generated `reference_V` Dataset variable instead.
