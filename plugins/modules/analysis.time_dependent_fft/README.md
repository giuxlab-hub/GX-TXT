# analysis.time_dependent_fft 1.3.3

External GX-TXT analysis plugin for dataset-native time-dependent FFT processing over Temporal Set `window_set` resources.

Minimum framework: **GX-TXT 0.9.7.97** (public dependency metadata).

## Numerical and graphics architecture

The FFT kernel uses public `NUMERIC_API_v1` operations. The current static
result-graph implementation uses its own compact scientific render cache and
is not yet fully integrated with the shared `plot.dataset` renderer. This
limitation does not change the authoritative time-frequency Dataset or the
module's documented cache-reuse behavior. See `MANUAL.md` for supported
calculation, presentation and export operations.

## Main behavior

- One canonical full-resolution time-frequency Dataset remains the scientific result.
- FFT windows execute through CORE Parallel Execution API v1.
- `Run mode = Auto` reuses a compatible existing FFT result and redraws plots without rerunning workers.
- `Run mode = Render only` guarantees no FFT recalculation.
- Plotting uses a compact bounded render cache built during calculation; it does not reread the huge long-form Dataset for normal graphs.
- Time-frequency 2D overview and 3D surface are global graphs.
- Window spectrum plotting can create **one separate file per selected temporal window**. Selecting all 55 windows produces 55 separate files, not a 55-panel figure.
- Full-resolution split CSV export remains optional and disabled by default.

## Window rule

```text
Window size = amount of signal analyzed by each FFT
Step        = distance between consecutive window starts
```

Example:

```text
Window size = 10 s
Step        = 5 s
```

means 50% overlap.

See `MANUAL.md` for the detailed user guide and troubleshooting.


## Plot variants

All three graph offerings support GX-TXT Plot Module API v1 variants. Use **Variants...** from the Analysis or Plots workspace to keep several persistent presentations of the same computed FFT result. Variants are intended for presentation experiments such as different temporal-window selections, display-reduction policies, labels, axis/display units, colormaps, color limits, 3D viewpoints, preview modes, legend settings, and output formats.

A variant does **not** recompute the FFT. GX-TXT gives each variant an isolated artifact directory, while `analysis.time_dependent_fft` reuses the current base scientific Render Cache. The base analysis must therefore have been calculated once for the current Dataset, Temporal Set, FFT window, detrend, NFFT and spectral representation. If those scientific inputs change, run the base analysis once again; the variants then reuse the new base result.

For `Window spectrum plots`, a variant with `All` selected still means one separate plot file per temporal window when individual export is enabled. Different variants can therefore retain different subsets or presentation settings without mixing them into one multi-panel figure.

Plot variants do not replace scientific calculation settings. Changing FFT weighting, detrending, NFFT or the spectral representation changes the analysis itself and belongs to the module calculation configuration rather than to a plot variant.
