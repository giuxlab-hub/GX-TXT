# Time-Dependent FFT — User Manual

The numerical frame kernel uses public NUMERIC_API transforms. Its current scientific graphics and large-data cache behavior are documented below; it does not use the Plot Dataset renderer for every result.

Module ID: `analysis.time_dependent_fft`  
Module version: `1.3.3`  
Minimum framework: GX-TXT `0.9.7.77`  
License: GNU GPL v3 or later

## 1. What this module does

Time-Dependent FFT answers a different question from a normal single FFT:

> How does the spectrum change while the signal evolves in time?

GX-TXT first divides the source signal into temporal windows through an existing **Temporal Set `window_set`**. The module performs one FFT for each resolved window and publishes one complete canonical time-frequency Dataset.

The scientific Dataset is kept as one result. Plotting is a separate stage and does not require splitting the scientific Dataset.

## 2. The two numbers that matter most: Window size and Step

These values belong to the Temporal Set, not to the FFT module itself.

### Window size

`Window size` is how much source signal one FFT sees.

Example with duration-based windows:

```text
Window size = 10 s
```

Each FFT therefore analyzes ten seconds of signal.

Example with sample-based windows:

```text
Window size = 4096 samples
```

Each FFT analyzes 4096 samples.

### Step

`Step` is how far the **start of the next window** moves forward.

Example:

```text
Window size = 10 s
Step        = 5 s
```

The windows are:

```text
Window 1:  0 ... 10 s
Window 2:  5 ... 15 s
Window 3: 10 ... 20 s
Window 4: 15 ... 25 s
```

The windows overlap by 5 s. Because 5 s is half of a 10 s window, this is **50% overlap**.

The general relation is:

```text
overlap fraction = 1 - Step / Window size
```

Examples:

```text
Window 10 s, Step 10 s  -> 0% overlap
Window 10 s, Step  5 s  -> 50% overlap
Window 10 s, Step  2 s  -> 80% overlap
Window 4096 samples, Step 2048 samples -> 50% overlap
```

### Samples versus Duration

If the Temporal Set says:

```text
Basis = Samples
Window size = 10
Step = 5
```

that means **10 samples** and **5 samples**, not seconds.

If you want physical time, create a duration-based Temporal Set, for example:

```text
Basis = Duration
Window size = 10 s
Step = 5 s
```

## 3. What one temporal window produces

Each temporal window produces one one-sided spectrum:

```text
frequency -> spectral value
```

If the Temporal Set resolves to 55 windows, the scientific result contains 55 spectra.

The published canonical Dataset is one complete long-form Dataset with:

```text
time
frequency
spectral_value
window_index
```

The module deliberately keeps this Dataset intact. It is not broken into 55 scientific datasets just to make plots.

## 4. Run mode — avoiding unnecessary FFT recalculation

The module separates scientific calculation from presentation.

### Auto — recommended

```text
Run mode = Auto
```

On the first run, the module performs the FFT calculation, publishes the Dataset and builds a compact render cache.

On later runs, if all scientific inputs are unchanged, the module **reuses the existing FFT result** and only redraws plots/exports.

Changing any of the following invalidates the scientific cache:

- source Dataset identity/stamp;
- time variable;
- signal variable;
- Temporal Set definition or resolved members;
- FFT weighting window;
- detrend mode;
- NFFT mode/value;
- spectral representation.

Changing presentation settings does **not** invalidate the FFT cache. Examples:

- plot titles;
- axis labels;
- colormap/viewpoint;
- selected windows for plotting;
- plot file format;
- display-density limits.

### Recalculate

```text
Run mode = Recalculate
```

Always reruns all FFT workers and republishes the scientific Dataset.

Use this only when you deliberately want a fresh calculation.

### Render only

```text
Run mode = Render only
```

Never starts FFT workers. It requires a compatible existing 1.3.0 render cache. If the cache is missing or scientifically stale, the run stops with an explicit diagnostic.

## 5. Why plotting no longer rereads the huge CSV

The full canonical Dataset can contain millions of time-frequency rows. Sending all of them to a renderer is usually pointless because a screen or PNG cannot display millions of independent pixels/vertices.

During the scientific calculation, version 1.3.0 therefore creates a **compact render cache while the FFT values are already in memory**.

The cache contains:

- every temporal window time;
- a common reduced frequency grid;
- peak-preserving values;
- local mean values.

The cache is bounded. It targets at most 4096 cached frequency cells per window and also applies a total-value budget for very large numbers of windows.

The full scientific Dataset is never reduced or replaced. Reduction exists only for presentation.

## 6. Display reduction

For overview/3D rendering, two display reductions are available:

### Peak

Keeps the maximum spectral value inside each display cell.

Useful when narrow spectral lines must remain visible.

### Mean

Uses the local mean value inside each display cell.

Useful for a smoother surface or average spectral-density presentation.

These operations affect only the plot representation. The canonical Dataset remains full resolution.

## 7. Plot products

### Time-frequency overview

One 2-D graph:

```text
X = time
Y = frequency
Color = spectral value
```

Default display reduction: `peak`.

### Time-frequency 3D surface

One global 3-D graph:

```text
X = time
Y = frequency
Z = spectral value
```

Default display reduction: `mean`.

This is one surface for the complete selected time range. It is not a multi-panel figure.

### Window spectrum plots

These are the individual FFT spectra.

If you select:

```text
Windows = All
```

and the Temporal Set has 55 windows, enabling individual plot export produces:

```text
55 windows -> 55 separate plot files
```

For example:

```text
window_plots/fft_window_0001.png
window_plots/fft_window_0002.png
...
window_plots/fft_window_0055.png
```

It does **not** create one 55-panel figure.

The stable Graph Provider artifact `03_selected_window_spectra.png` is only a preview. By default it shows the first selected window. You can explicitly choose an overlay preview if you want several selected curves on one plot.

## 8. Choosing which windows to plot

The Window spectrum plots configuration supports:

### All

All resolved Temporal Set windows.

### Index range

Example:

```text
First = 10
Last  = 20
```

plots windows 10 through 20.

### Explicit list

Example:

```text
1,5,12-20
```

plots window 1, window 5 and windows 12 through 20.

### Time range

Select windows whose representative time falls inside the requested interval.

The time values use the source/canonical time unit shown by GX-TXT.

## 9. Maximum displayed windows / frequency bins

These settings are **plot-density limits only**.

For example:

```text
Maximum displayed frequency bins = 2048
```

does not change NFFT and does not delete Dataset rows. It only limits the amount of information sent to the graphics renderer.

Using `0` means no additional reduction at that plotting stage, but the data still come from the bounded render cache rather than from millions of full-resolution CSV rows.

## 10. Separate per-window CSV export

This is independent from plotting.

```text
Separate per-window data export = none
```

is the recommended default.

Options:

```text
none
selected_windows
all_windows
```

During a fresh calculation, requested split CSV files are written directly from the FFT worker results before those temporary results are discarded. The module does not rescan the large published Dataset.

During a render-only/reuse run, an explicitly requested split export uses a single streaming pass through the canonical Dataset.

Because split CSV export is full-resolution data export, it can legitimately be expensive. Do not enable `all_windows` unless you actually need separate data files.

## 11. FFT weighting windows

Available weighting functions:

```text
rectangular
hann
hamming
blackman
blackman_harris
flat_top
```

Amplitude normalization uses coherent gain (`sum(w)`). PSD normalization uses `fs * sum(w.^2)`.

## 12. Detrending

```text
none
mean
linear
```

`mean` removes DC before windowing and is the normal default.

## 13. NFFT

### Auto

Uses the resolved full Temporal Set window length in samples.

### Explicit

Uses the requested NFFT. It must be at least as large as a full resolved window. A larger value performs zero padding; it does not create additional measured information.

## 14. Spectral representations

### amplitude

One-sided amplitude spectrum with weighting-window coherent-gain correction.

### psd

One-sided power spectral density normalized by sampling frequency and window energy.

### amplitude_db

Amplitude result represented in dB relative to numerical amplitude 1. It is not automatically dBFS unless the source amplitude itself has that convention.

## 15. Sampling requirements

The signal must be uniformly sampled.

Canonical uniform axes use their `origin / step / count` metadata efficiently.

Explicit time columns are validated. Strongly non-uniform sampling is rejected rather than silently interpreted as uniform.

## 16. Parallel execution

Each Temporal Set window is an independent work item submitted through CORE Parallel Execution API v1.

```text
workers = auto
workers = serial
workers = N
```

The framework remains authoritative for worker limits, nested-parallel protection and recommended internal numerical threads.

Worker count does not change the scientific result and does not invalidate the plot cache.

## 17. Plot customization

GX-TXT Graph configuration remains authoritative for presentation. Depending on the graph, you can configure:

- title;
- X/Y/Z labels;
- color label;
- display units supported by GX-TXT;
- colormap/colorbar through common graphics configuration;
- maximum displayed windows/bins;
- peak/mean display reduction;
- additional PDF/SVG output;
- individual-window PNG/PDF/SVG format;
- individual basename;
- individual title template.

Useful title-template fields are:

```text
{index}
{member_id}
{time}
```

## 18. Typical workflows

### First analysis

```text
Run mode = Auto
Select source Dataset / time / signal
Select Temporal Window Set
Choose FFT parameters
Run
```

GX-TXT calculates, publishes and builds the render cache.

### Change only plots

```text
Run mode = Auto
change plot title / labels / selected windows / format
Run
```

The compatible FFT result is reused. No FFT workers are launched.

For an explicit guarantee:

```text
Run mode = Render only
```

### Generate 55 separate window plots

Enable `Window spectrum plots`, then:

```text
Windows to plot/export = All
Write one separate plot file per selected window = Yes
Individual plot format = PNG
```

With 55 windows you obtain 55 files in `window_plots/`.

## 19. Troubleshooting

### The module recalculates when I expected only plotting

Use `Run mode = Render only` to verify reuse. If it reports an incompatible cache, one of the scientific inputs changed or the cache was generated by an older module version.

### Plotting is slow

Check that you are using 1.3.0 or later. Graph rendering should use the compact render cache rather than rereading the entire long-form Dataset.

Also check whether you explicitly enabled:

```text
Separate per-window data export = all_windows
```

Full-resolution split data export is separate from plotting and may be expensive.

### I selected 55 windows but see only one preview PNG

The stable Graph Provider file is a preview. Enable:

```text
Write one separate plot file per selected window = Yes
```

The 55 separate files are written under `window_plots/`.

### I do not understand the Temporal Set settings

Remember the simplest rule:

```text
Window size = how much signal each FFT sees
Step        = how far the next FFT moves forward
```

For 50% overlap, Step is half of Window size.

## 20. Public GX-TXT APIs used

The module uses the public GX-TXT interfaces declared in `module.ini`, including:

- Analysis Source Map / runtime access;
- Canonical Dataset / Variable Schema;
- Dataset Metadata;
- Temporal Set API v1;
- Table Stream API v3;
- Dataset Publication API v2 / Storage Auto;
- Parallel Execution API v1;
- elapsed-time and Unit Registry infrastructure;
- Graph Provider / common plotting APIs;
- Render Cache API v1;
- Progress API;
- Plugin Install API;
- Documentation API v1.

No private parallel scheduler or private Dataset registry is implemented.

## 21. Help inside GX-TXT

The normal GX-TXT **Help** dialog displays the module's built-in Quick Guide from the descriptor. It summarizes Window size, Step, overlap, Samples versus Duration, Run mode, graph meanings and window selection.

This `MANUAL.md` is the complete reference shipped with the plugin.


## Plot variants

All three graph offerings support GX-TXT Plot Module API v1 variants. Use **Variants...** from the Analysis or Plots workspace to keep several persistent presentations of the same computed FFT result. Variants are intended for presentation experiments such as different temporal-window selections, display-reduction policies, labels, axis/display units, colormaps, color limits, 3D viewpoints, preview modes, legend settings, and output formats.

A variant does **not** recompute the FFT. GX-TXT gives each variant an isolated artifact directory, while `analysis.time_dependent_fft` reuses the current base scientific Render Cache. The base analysis must therefore have been calculated once for the current Dataset, Temporal Set, FFT window, detrend, NFFT and spectral representation. If those scientific inputs change, run the base analysis once again; the variants then reuse the new base result.

For `Window spectrum plots`, a variant with `All` selected still means one separate plot file per temporal window when individual export is enabled. Different variants can therefore retain different subsets or presentation settings without mixing them into one multi-panel figure.

Plot variants do not replace scientific calculation settings. Changing FFT weighting, detrending, NFFT or the spectral representation changes the analysis itself and belongs to the module calculation configuration rather than to a plot variant.
