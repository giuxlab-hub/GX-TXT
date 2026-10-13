# SIGNAL_API_v1

Provider: `math.signal` 1.2.0. API ID/version: `SIGNAL_API_v1`/1. This service supplies reusable signal and LTI mathematics for imported or measured data. It produces values and diagnostics; Dataset publication belongs to the existing GX-TXT Publication API. GNU Octave 9.4 and installed signal/control packages are the current backend. Operations are serial and create no worker pool.

## Public bindings and discovery

- GNU Octave: `gxtxt_signal_v1(family, action, a, b, c, options)`.
- Tcl: `::GX::SignalAPIv1::call family action a b c ?options?` after `::GX::modulePublicApiActivate math.signal SIGNAL_API_v1`.
- Registered Octave/Python scripts: `gxtxt_api_require('SIGNAL_API_v1@1:math.signal')`, then `gxtxt_api_call('SIGNAL_API_v1','family.action',{a,b,c,options})` in Octave or a Python list of the same operands.
- `::GX::SignalAPIv1::apiInfo`, `listOperations`, and `operationMetadata id` expose machine-readable provider identity and the operation catalog. The Script Bridge describes each operation as well.

The Tcl and Script Bridge bindings use typed nodes. An array is `{kind=array, shape=[rows,columns,...], real=[values in column-major order], imaginary=[optional matching values]}`. Other nodes are `{kind=empty}`, `{kind=text,value=...}`, `{kind=cell,items=[nodes]}`, and `{kind=struct,fields={name:node}}`. Results use real/imaginary pairs (`value_real`, `value_imaginary`) and explicit numerical fields. Dimensions in array nodes are positive; NaN/Inf inputs are rejected. Units are caller-owned except explicit `time`, `frequency_hz`, and rate fields. The API never guesses sampling intervals.

## Operations

Every row uses the common signature `(family, action, a, b, c, options)`. Optional operands are `[]` in direct Octave or an empty typed node through the Bridge. Direct Octave accepts ordinary numeric arrays and structs. The operation IDs are `family.action` in `api/operations_v1.tsv`.

| Family | Actions and operands | Returned fields and assumptions |
|---|---|---|
| `convolution` | `linear`, `circular`, `deconvolve`; `a=x`, `b=h` | Linear and circular convolution. Deconvolution uses a frequency-domain regularization parameter and rejects ill-conditioned unregularized kernels. |
| `correlation` | `auto`, `cross`, `delay`; `a=x`, `b=y` | Correlation, integer lags, peak delay. `normalization=none|biased|unbiased|coefficient`; complex correlation conjugates the second signal. `sample_rate` adds seconds. |
| `filter` | `inspect`, `causal`, `zero_phase`, `sos`; `a` model struct with numerator/denominator or SOS, `b` samples, `c` initial state | Causal final state, pole stability and zero-phase output. Zero-phase requires sufficient samples and stable IIR poles. SOS has six coefficients per section and one two-sample state row per section. |
| `design` | `butterworth`, `chebyshev1`, `chebyshev2`, `elliptic`, `bessel`, `fir_window`, `estimate_order`; order and cutoff or pass/stop edges | Numerator/denominator and pole fields; SOS for digital IIR order above one. `band=low|high|bandpass|stop`, `domain=discrete|analog`. Digital cutoff is normalized to Nyquist; analog cutoff is in rad/s. FIR windows: Hamming, Hann, Blackman. Order estimation uses pass/stop ripple specifications. |
| `multirate` | `decimate`, `interpolate`, `rational`; samples and integer up/down factors | Anti-alias filtering uses the installed signal package. `sample_rate` or a validated uniform `input_time` adds output rate and coordinates; `start_time` preserves a declared origin. |
| `lti` | `inspect`, `tf`, `zpk`, `ss`, `zoh`, `foh`, `tustin`, `prewarp`, `matched`; `a` model struct | SISO TF/ZPK/state-space conversions, poles, zeros and stability; MIMO state-space inspection/discretization. Model `kind=tf|zpk|ss`, `domain=continuous|discrete`, and explicit `sample_period` for discrete systems. Conversion to discrete requires an explicit new sample period; prewarping also requires `prewarp_hz`. |
| `response` | `evaluate`, `frequency`, `impulse`, `step`, `input`; model and evaluation vector | Complex SISO response, magnitude, unwrapped phase, group delay and time response; MIMO state-space frequency response returns frequency × output × input. Frequency input is Hz; time input is seconds. `input` accepts initial state in options. |
| `spectral` | `periodogram`, `welch`, `asd`, `cross_psd`, `coherence`, `frf_h1`, `frf_h2`, `window_metrics`; samples, second signal where needed, sample rate | PSD/ASD/FRF and frequency axis; window coherent gain, power gain and ENBW. Window, overlap fraction and NFFT are explicit options. Welch/FFT analysis modules remain separate workflows. |
| `stft` | `forward`, `inverse`; samples or full two-sided STFT, window, hop | Full complex STFT, sample/frequency bins, optional Hz/seconds axes; inverse uses overlap-add and reports minimum/maximum overlap weight. `pad=true` supports endpoint-zero windows such as Hann; pass returned `pad_left` and `original_length` to inverse options to trim. Uncovered retained samples fail. |
| `cepstrum` | `real`, `complex`, `inverse`, `lifter`; samples or cepstrum and explicit magnitude floor/quefrency range | Real cepstrum, unwrapped complex cepstrum with inverse, and lifter. Phase branch and magnitude floor are declared; inverse applies to the complex cepstrum. |
| `wavelet` | `dwt`, `inverse_dwt`, `cwt`, `scalogram`; samples and levels/scales | Periodic orthogonal DWT with Haar/db1, db2 and sym2; Morlet or `mexican_hat` CWT at explicit scales; scalogram returns power and coordinate axes. |
| `generate` | `sine`, `multi_tone`, `chirp`, `square`, `pulse`, `impulse`, `white_noise`, `colored_noise`, `am`, `fm`; explicit time axis or count/rate | Deterministic test waveforms. Noise requires a declared seed; rates, phase and duty are explicit. |
| `analytic` | `signal`, `envelope`, `phase`, `instantaneous_frequency`; real signal, rate for frequency | Hilbert analytic signal, amplitude and unwrapped phase. Instantaneous frequency is in Hz. |
| `frequency_metric` | `gain`, `group_delay`, `phase_delay`, `peak`, `resonance`, `bandwidth`, `q`, `margins`; frequency and complex response | Gain and dB/phase, -3 dB crossing bandwidth, Q, loop-response margins. Margins require the caller to declare that the response is a loop transfer; no feedback interpretation is inferred from data alone. |
| `time_metric` | `step`, `slew`, `pulse`; time and real signal | Explicit thresholds for rise/fall time, settling, overshoot/undershoot, slew, pulse width/duty and period jitter. A step's baseline and final value can be declared. |
| `quality` | `basic`, `snr`, `harmonics`, `spectrum`; signal, optional noise, sample rate | RMS, peak, crest factor, DC, SNR and coherent-bin harmonic power/THD. `spectrum` reports THD+N, SINAD, SFDR, ENOB, noise power and median noise floor per bin; it rejects a noncoherent fundamental frequency to avoid mislabeled leakage. |
| `events` | `crossings`, `period`, `delay`; time, real signal, optional second signal | Linearly interpolated threshold crossings and event timing. Crossing direction is explicit. |

Errors use `GXTXT:Signal:*` identifiers in Octave and structured `GXTXT SCIENTIFIC <identifier>` Tcl codes. Empty, nonfinite, dimensionally inconsistent and invalid policy inputs fail explicitly. Singular deconvolution and zero-energy normalization fail unless the caller chooses a valid conditioning policy. Time and frequency axes must be strictly increasing where used. Complex values are supported for convolution, correlation, filtering, spectral and LTI operations; threshold events and step metrics require real values.

FIR window high-pass and band-stop designs require even order; an odd request fails rather than silently increasing the order. Low/high designs require one edge, while band-pass/stop designs require two increasing edges.

Complex TF/ZPK and state-space inspection, frequency evaluation, impulse/step/input response and ZOH/bilinear conversion use explicit polynomial, matrix-exponential or ODE operations because the installed control package discards imaginary coefficients in several paths. Complex FOH and matched-pole conversion use the explicit complex-coefficient path. Real MIMO state-space frequency/time response is supported; conversion to a scalar TF or ZPK is undefined. For a continuous impulse with direct feedthrough, the returned sample series is the regular response and `direct_feedthrough_real/imaginary` reports the separate Dirac coefficient.

## Examples

```octave
r = gxtxt_signal_v1('convolution','linear',[1;2],[1;1],[],struct());
assert(isequal(r.value_real,[1;3;2]));
```

```python
from gxtxt import gxtxt_api_require, gxtxt_api_call
gxtxt_api_require('SIGNAL_API_v1@1:math.signal+convolution')
a = {'kind':'array','shape':[2,1],'real':[1,2]}
b = {'kind':'array','shape':[2,1],'real':[1,1]}
r = gxtxt_api_call('SIGNAL_API_v1','convolution.linear',[a,b,{'kind':'empty'}])
```

```octave
gxtxt_api_require('SIGNAL_API_v1@1:math.signal+convolution');
a=struct('kind','array','shape',[2 1],'real',[1 2]);
b=struct('kind','array','shape',[2 1],'real',[1 1]);
r=gxtxt_api_call('SIGNAL_API_v1','convolution.linear',{a,b,struct('kind','empty')});
```
# Guided-client metadata

`operationMetadata(id)` also returns `arguments`, `argument_descriptors`,
`signature`, `worksheet_example`, `result_fields`, and `unit_behavior`.
These fields are derived from the provider-owned operation and family
contracts. They let a Worksheet or other guided client display the public
call's inputs and unit/result expectations without parsing implementation
code. The existing `call(family, action, a, b, c, options)` contract is
unchanged.

## Local bulk scientific transport

The public v1 API and complete default results are retained. Large arrays use
scoped binary buffers and a per-job Octave context through the existing provider
bindings. The public Script Bridge and Dataset API contracts specify shape, dtype,
resource limits, optional Signal uniform grids/result projection and output bindings.
