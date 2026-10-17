# dev097 / 1.2.0

- Numeric owns RMS/level calculation; CORE owns interpretation, units and reports.
- Both per-band compact semantics and the power summary accompany publication.
- Zero band power retains an undefined finite-level state; all-zero runs finish
  with valid power/RMS plots and an explicitly unavailable dB variant.
- Earlier finite dB images move into owned analysis history without byte changes.
- Preserved band integration and scientific identities; declared Numeric and
  Plot Dataset dependencies. Tested actual modules and both Script Job languages.

# Changelog

## 1.1.0

- Removed the module-private scientific renderer, render cache and rerender path.
- Published the three standard band views (level, RMS and power) as persistent `plot.dataset` / `PLOT_DATASET_API_v2` variants.
- Added exact interval-bar use of public `bar_x_bounds`, binding every bar to the published `lower_frequency` / `upper_frequency` variables.
- Kept fractional-octave band definitions and PSD-bin overlap integration in the module because they are domain workflow semantics rather than generic NUMERIC_API primitives.
- Presentation-only changes now use normal `plot.dataset` persistence/rerender without recomputing band integration.

## 1.0.1

- Render band intervals as visible outlined bars on the supported headless GNUplot backend. The previous filled-polygon path produced a blank data area despite valid scientific results.
- Preserve each band's exact lower and upper frequency edges and computed level. The line style and scientific integration are unchanged.

## 1.0.0

- Initial external release.
- Exact base-10 1/1, 1/3 and 1/6-octave band definitions.
- Streaming linear-PSD integration with fractional frequency-bin overlap at band boundaries.
- Dataset Publication v2 / Storage Auto output.
- Band power, band RMS, configurable-reference dB level and coverage diagnostics.
- Cache-only rerender and `module_cache` Graph Provider variants.
- Deterministic student Session Generator.
- Correct the full-range Table Stream requests used by the scan and integration stages (`count=-1`); `count=0` represents an empty range in API v3.
