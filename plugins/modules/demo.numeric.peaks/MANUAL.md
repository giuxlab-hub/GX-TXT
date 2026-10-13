# Numerical Peak Detection Demo — Manual

## Purpose

`demo.numeric.peaks` is an external demonstration/reference plugin for GX-TXT 0.9.7.82. It demonstrates the public Dataset-aware peak primitive supplied by `math.numeric` through `NUMERIC_API_v1`. It is not a production chromatography, spectroscopy or signal-processing workbench.

## Installation

Install `demo.numeric.peaks_1.0.0.zip` through GX-TXT Plugin Install. The package requires GX-TXT 0.9.7.82 or later compatible 0.9.7.x behavior and depends on the bundled `math.numeric` service.

The plugin package contains a portable Session Generator package:

```text
session_generators/gxtxt_numerical_examples_peak_detection_1.0.0.zip
```

Import that package into the existing `GX-TXT Numerical Examples` library with the Session Generator Library Manager.

## Demonstration Session and Dataset

Generate:

```text
GX-TXT Numerical Examples
→ Mathematics
→ Peak Detection
```

The generator creates a normal Session containing:

```text
raw/peak_detection_demo.csv
metadata/ground_truth.txt
```

The CSV is deterministic and contains 101 samples with columns:

```text
sample
x_s
signal_V
```

The signal is an analytical baseline plus three separated Gaussian-like peaks centered at approximately 20 s, 50 s and 78 s. Import the CSV through normal GX-TXT Acquisition as a `table.generic` Canonical Dataset, for example `peaks.source`. Assign `s` to `x_s` and `V` to `signal_V`.

`ground_truth.txt` is only for tests and human inspection. The plugin never reads it during normal analysis.

## Bindings

Configure one Analysis Source Dataset and bind:

```text
Independent X variable → x_s
Signal Y variable      → signal_V
```

Bindings are resolved through stable Dataset `variable_id` identity. The plugin does not bind by CSV column number, filename or display label alone.

An optional normal GX-TXT X-range Dataset Selection may be applied. The Selection X variable must match the bound X variable.

## Public peak API used

The module calls the real public operation:

```text
NUMERIC_API_v1
→ dataset_find_peaks
```

The underlying public peak primitive returns:

```text
indices
x
heights
prominences
widths
left_x
right_x
n
```

The plugin does not implement local-maxima search, prominence or width calculations privately.

## Peak options

GX-TXT 0.9.7.82 exposes these peak options and the demo exposes the same meaningful subset:

```text
Minimum peak height
Minimum prominence
Minimum peak distance
Distance units: x | samples
Width relative height
NaN / Inf policy: omit | error
```

The generated example defaults are:

```text
min_height       = 0.5
min_prominence   = 0.5
min_distance     = 8
distance_mode    = x
relative_height  = 0.5
nonfinite        = omit
```

`min_height` is an absolute Y-value threshold. `min_prominence` is expressed in the Y quantity unit.

## Peak position and distance semantics

`peak_index` is the public 1-based index in the valid selected signal passed to `NUMERIC_API_v1`. `peak_x` is the actual scientific X coordinate from the bound X variable.

For `distance_mode=samples`, `min_distance` is measured in sample-index spacing. For `distance_mode=x`, it is measured directly in the bound X coordinate and therefore has the X unit.

The public operation accepts non-uniform X coordinates. X must be strictly increasing after Dataset Selection and the selected non-finite policy.

## Prominence and width semantics

Prominence is returned directly by `NUMERIC_API_v1` and retains the Y unit.

For each accepted peak, the public API evaluates the width crossing level as:

```text
peak_y - relative_height * prominence
```

It returns left and right interpolated X crossings. The plugin publishes:

```text
width = right_x - left_x
```

as supplied by the public result. With the default `relative_height=0.5`, this is width at half prominence. It is not described as a separate private FWHM algorithm.

## Non-finite policy

GX-TXT 0.9.7.82 uses an explicit public policy:

```text
error
omit
```

`error` rejects NaN/+Inf/-Inf in X/Y. `omit` discards affected X/Y pairs before the public peak operation. Invalid samples are never converted to zero.

## Run workflow

A normal workflow is:

```text
Generate Session
→ import peak_detection_demo.csv
→ enable demo.numeric.peaks
→ select peaks.source
→ bind x_s and signal_V
→ keep or adjust public peak options
→ Run
```

## Published Dataset

The default output Dataset ID is:

```text
demo.numeric.peaks.detected
```

It is a normal Canonical `table.generic` Dataset published through Dataset Publication API v2. Its columns are:

```text
peak_id       dimensionless sequential identifier
peak_index    dimensionless public 1-based peak index
peak_x        X unit
peak_y        Y unit
prominence    Y unit
width         X unit
left_x        X unit
right_x       X unit
```

Only values genuinely returned by the public API are published. The source Dataset is never modified. Publication provenance records the producer/plugin version, source Dataset, source X/Y variable IDs, Selection and peak configuration.

## Report

`peak_detection_report.txt` records the source Dataset, X/Y variables and units, Selection, `dataset_find_peaks`, non-finite policy, sample counts, configuration, detected peak count, X positions, amplitudes, prominence, width and warnings.

## Graph

`01_peak_detection.png` is an automatic Graph Provider artifact rendered with the normal GX-TXT shared graphics helpers. It shows the selected valid source signal as a line and the detected public peak X/Y coordinates as markers. The marker coordinates are the same values used for the published peak Dataset.

Graph appearance can be rerendered from `render_cache.mat` without recalculating peak detection.

## Save/reopen

Normal module configuration and Dataset Selection are stored by the framework Session manifest. The published Dataset remains a normal Session Dataset and is rediscovered after reopening the Session according to standard GX-TXT persistence rules.

## Known limitations

This first demonstration intentionally exposes only the public peak primitive available in GX-TXT 0.9.7.82. There is no baseline correction chain, peak fitting, deconvolution, area integration, spectral assignment or alternative detector in this plugin. Endpoints are governed by the public local-maxima implementation; the demo does not add special endpoint detection. Width filtering and maximum-width filtering are not public `find_peaks` options in 0.9.7.82 and are therefore not invented by this plugin.

## Validation

Static/package tests verify Plugin Install metadata, Analysis Source bindings, the exact public API operation/options, deterministic source generation, and absence of a private peak algorithm. Runtime tests exercise no-peak, single-peak, multiple-peak, equal-height, near-edge, non-uniform-X and non-finite cases through `NUMERIC_API_v1` when GNU Octave is available. Runtime-dependent tests are reported as `SKIP` when Octave is unavailable rather than being reported as PASS.
