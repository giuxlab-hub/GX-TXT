# GX-TXT 0.9.8.04 — Remaining Work / Handover

SPDX-License-Identifier: GPL-3.0-or-later

## Delivery status

**This is a partial development checkpoint, not a completed time-dependent FFT migration.**
The source baseline is `gxtxt_pipeline_v09803.tar.gz`, SHA-256
`aadde2edea8e4b240498a7bbf38c3e9f29b94933d4cab7fd1065cebe69974a67`.
The delivered framework identifies as 0.9.8.04 and includes
`analysis.time_dependent_fft` 1.3.2. `math.numeric` remains 1.5.0 and
`plot.dataset` remains 3.7.0.

The numerical FFT kernel now consumes the existing public FFT, one-sided
transform, detrending and symmetric-window operations. Frequency coordinates
come from the public frequency-grid operation. Worker grid statistics are read
through `NUMERIC_API_v1`, while the original **mean-relative** timing tolerance
formula is retained (the service's median-relative diagnostic is not equivalent).
Production discovers the advertised binding from `runtime.ini`; no private
provider path or fallback mathematical implementation has been introduced.

The private static renderer has **not** been migrated in this checkpoint.
It is retained explicitly as unfinished legacy code, not as an architectural
exception or a pattern to copy. Do not remove this module from either migration
TODO until the remaining work and actual execution checks pass.

## 1. Complete graphics migration without losing large-data behavior

Relevant files:

- `plugins/modules/analysis.time_dependent_fft/runtime/analysis_time_dependent_fft_render.m`
- `plugins/modules/analysis.time_dependent_fft/runtime/analysis_time_dependent_fft_main.m`
- `plugins/modules/analysis.time_dependent_fft/runtime/analysis_time_dependent_fft_rerender_main.m`
- `plugins/modules/analysis.time_dependent_fft/runtime/tdfft_reduce_values.m`
- `plugins/modules/analysis.time_dependent_fft/runtime/tdfft_reduce_grid.m`
- `plugins/modules/plot.dataset/runtime/pd_prepare_3d.m`

Move overview, 3-D surface, window preview, and individual-window file rendering
through the public `plot.dataset` / Graph Provider path. Keep normal shared
axis/legend/color/export/persistence controls. Add a public generic capability
first if the current contract cannot consume a bounded, reproducible display
representation. Do not replace the old renderer with another private renderer.

**A direct substitution of the huge canonical long-form Dataset is unsafe.**
In the inspected 3.7.0 `pd_prepare_3d.m`, `prepare_gridded` accumulates all valid
X/Y/Z rows and constructs the full rectangular matrix before applying
`grid_stride`. Chunked reading there does not bound the final in-memory grid.
This is a verified code-path concern, not a measured out-of-memory result.

The old time-dependent FFT workflow instead builds a compact peak/mean cache
while each worker result is already available. Preserve that optimization in
shared infrastructure, or supply an equivalent public mechanism that avoids
both full-Dataset rescans and full-grid materialization for ordinary rerenders.
The display representation must remain explicitly derived; it must not replace
or silently reduce the full-resolution scientific Dataset.

Preserve these existing behaviors:

- Workers read only the selected temporal window through Table Stream, in
  chunks of at most 65,536 rows; they do not load the whole source Dataset.
- Canonical publication is append-based, full resolution, and uses Storage Auto.
- The compact cache carries both peak-preserving and mean-reduced grids.
- Current cache planning targets at most 4,096 frequency bins and 4,000,000
  values **per** peak/mean matrix. Two float64 matrices at that budget alone
  use 64,000,000 bytes, excluding temporary arrays and metadata.
- Overview defaults: 256 displayed windows x 2,048 frequency bins, peak mode.
- Surface defaults: 128 displayed windows x 1,024 frequency bins, mean mode.
- Ordinary rendering does not reread the scientific long-form Dataset.
- `Auto`, `Render only`, and presentation variants do not rerun FFT workers
  when a compatible source/settings fingerprint is available.
- Window selection, first-selected preview, optional overlay, and one file per
  selected window remain distinct; do not turn them into one giant multipanel plot.
- Split CSV export stays disabled by default; requested re-export uses one
  streaming pass, not one full scan per window.
- Old caches retain their actual producer metadata. Compatible 1.3.0/1.3.1/1.3.2
  cache schemas remain accepted, subject to source/settings fingerprint checks.

### Existing limits still to address

The cache budget is a target, not an unconditional constant-memory guarantee:
when the number of windows exceeds 4,000,000, keeping at least one value per
window exceeds it. Cache size, member metadata and worker-result files also
still grow with the number of windows. Display settings with zero limits and
large selected-window overlays can deliberately increase memory/output work.
Keep these limitations explicit; decide on generic budgets or streaming display
storage before claiming arbitrary-size support.

## 2. Finish the numerical audit

The FFT kernel and transform-coordinate path are migrated, but this does not
complete the whole-module numerical audit. Review the remaining generic
reductions in `scan_explicit_timing`, `tdfft_reduce_values` and `tdfft_reduce_grid`.
Do not replace an O(N) streaming reduction with an expensive all-statistics
operation that also sorts or materializes all data merely to obtain a mean.
If an efficient generic reduction contract is missing, extend `math.numeric`,
test it centrally, then consume it here. Preserve window orchestration,
representation semantics and scientific tolerance definitions in the module.

The worker still applies the inherited `fftw('threads', ...)` recommendation.
Move backend-specific thread control behind an appropriate shared public
execution/numerical contract when completing the audit, without losing CORE
Parallel Execution's protection against nested oversubscription.

Do not change amplitude, one-sided DC/Nyquist factors, PSD normalization,
window definitions, temporal coordinates, or result ordering unintentionally.

## 3. Execute the missing real-runtime checks

This delivery environment has neither `octave-cli` nor `octave`.
The Python reference and Tcl scheduler checks do **not** execute the modified
Octave scientific implementation. Real Octave execution is still required.

From an extracted candidate tree:

```sh
export GXTXT_FRAMEWORK_ROOT="$PWD"
bash plugins/modules/analysis.time_dependent_fft/tests/run_tests.sh
```

The suite includes real-kernel checks, public-binding delegation, cache-version
compatibility, and actual Octave serial/parallel tests when Octave is installed.
Extend/run direct old-vs-new kernel comparisons for all six windows, all three
detrend modes, odd/even transform sizes, zero padding, DC, Nyquist, amplitude
and PSD. The public detrend implementation uses a conditioned polynomial fit;
allow justified floating-point tolerance, not merely identical-text assertions.

On a **copy** of a real large session, validate:

1. Fresh compute and numerical output against 0.9.8.03.
2. Reopen and Render only: no FFT worker launch and no scientific Dataset scan.
3. Change title/ranges/units/colormap/variant only: no scientific recomputation.
4. Change scientific settings: reject stale cached results.
5. Narrow spectral lines and brief time transients survive peak reduction.
6. Memory and disk behavior with a representative large recording.
7. All intended shared graphical workflows after graphics migration.

No real rendering, complete scientific session execution, or large-file
performance benchmark is claimed in this checkpoint.

## 4. Verify earlier migrated modules separately

This checkpoint preserves time-dependent FFT's existing renderer, reductions,
window selection and export helpers byte for byte (verified by SHA-256 against
the 0.9.8.03 extraction). It does **not** prove that every earlier migrated
module retained all previous large-file protections.

Compare the historical and current plotting paths for cepstrum, cross-spectral
transfer, envelope, fractional-octave, harmonic analysis, spectral features,
IR spectroscopy and UV/Vis. Check pre-read vs post-read reduction, full-grid or
family materialization, multiple scans, cache reuse, limits, and peak preservation.
Record each actual finding without assuming the shared API automatically
preserves the old module's performance behavior.

## TODO maintenance

Remove a remaining item only after its implementation and relevant checks are
complete. Keep history in CHANGELOG / release notes, not as checked-off TODOs.
