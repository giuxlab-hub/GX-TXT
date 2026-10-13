# GX-TXT Computed Data Annotation API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

This API is the framework-owned channel for **module-produced scientific annotations in canonical data coordinates**. It is distinct from the existing interactive Plot Annotation API, whose objects are user-authored and stored in `figure_norm` coordinates.

Typical producers include FFT/spectrum analysis, Bode analysis, peak finding and crossing detection. Typical annotations are the fundamental, harmonics, SFDR spur, cutoff frequency, phase/gain margins, peaks and thresholds.

Computed annotations are declarative metadata attached to a canonical dataset. They do not modify dataset values and are not a second dataset.

## Publication contract

A producer writes a UTF-8 INI sidecar inside its normal module output directory and references it from Dataset Publication API v1:

```octave
ann{1}=struct('id','fundamental','type','vline', ...
  'x',1000,'x_variable','frequency_Hz','x_unit','Hz', ...
  'label','Fundamental','style_hint','primary');
ann{2}=struct('id','sfdr','type','point', ...
  'x',17320,'x_variable','frequency_Hz','x_unit','Hz', ...
  'y',-67.4,'y_variable','magnitude_dBc','y_unit','dB', ...
  'label','SFDR spur','style_hint','spur');

gxtxt_data_annotations_write(outdir,'spectrum.annotations.ini', ...
  'fft.spectrum',ann);
meta.computed_annotations='spectrum.annotations.ini';
gxtxt_dataset_publish_request(outdir,'fft.spectrum','spectrum.table','csv', ...
  'spectrum.csv',meta);
```

The framework validates the sidecar during dataset publication and stores its session-relative path in the Dataset Registry as:

```ini
computed_annotations_api_version=1
computed_annotations_file=analysis/<producer>/spectrum.annotations.ini
```

The sidecar therefore travels with the session/export together with the dataset.

## Sidecar format

```ini
[annotations]
api_version=1
dataset_id=fft.spectrum
count=3

[annotation.1]
id=fundamental
type=vline
x=1000
x_variable=frequency_Hz
x_unit=Hz
label=Fundamental
style_hint=primary

[annotation.2]
id=harmonic_2
type=vline
x=2000
x_variable=frequency_Hz
x_unit=Hz
label=2nd harmonic
style_hint=harmonic

[annotation.3]
id=sfdr_spur
type=point
x=17320
x_variable=frequency_Hz
x_unit=Hz
y=-67.4
y_variable=magnitude_dBc
y_unit=dB
label=SFDR spur
style_hint=spur
```

Supported v1 types:

- `vline`: requires `x`, `x_variable`, `x_unit`;
- `hline`: requires `y`, `y_variable`, `y_unit`;
- `point`: requires both X and Y triplets;
- `text`: requires both X and Y triplets and anchors the label at that data coordinate.

Optional fields:

- `label` — human-readable text;
- `style_hint` — semantic rendering hint. v1 recognizes `primary`, `secondary`, `harmonic`, `spur`, `threshold`, `warning`; unknown values fall back to the normal computed-annotation style.

Coordinates MUST be expressed in the declared source units of the canonical variables. The sidecar must reference canonical variable names, not PNG geometry and not display-scaled values.

## Consumer runtime

For every selected Analysis Source carrying a sidecar, the framework adds:

```ini
[computed_data_annotation_api]
api_version=1

[analysis_source.primary.computed_annotations]
api_version=1
dataset_id=fft.spectrum
file=/absolute/session/path/analysis/fft.module/spectrum.annotations.ini
```

Public Octave reader:

```octave
A = gxtxt_data_annotations_from_runtime(runtime_cfg,'primary');
```

Framework plotters can then render the objects with:

```octave
gxtxt_plot_data_annotations_2d(ax_left,ax_right,A,context);
```

The context maps canonical X/Y variable names to the active left/right plot axes and their display units. Unit conversion is framework-owned through Unit/Dimension API. Canonical dataset data are never changed.

## Layering and interaction with user annotations

Computed annotations and user annotations are separate layers:

```text
scientific traces
  -> computed data-coordinate annotations
  -> exported base plot
  -> interactive user figure_norm annotations
```

The existing `annotation_editor=standard` editor edits only user annotations. It never edits or deletes computed annotations.

Computed annotations are reproduced on cache-only rerender because the plotter reads the dataset sidecar again and converts coordinates to the current display units.

## v1 limitations

- 2D data-coordinate rendering only;
- no 3D annotation objects;
- no free-form arbitrary drawing commands;
- no implicit search for peaks/crossings: the producing scientific module computes them;
- style is a framework-owned hint, not an unrestricted plotting command.
