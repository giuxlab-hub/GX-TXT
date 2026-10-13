# GX-TXT Level Scale API v1

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in 0.9.7.9. A level scale is a presentation transform, separate
from source and display units. The default is linear and preserves historical
behavior. No numeric conversion is inferred from a unit symbol such as dB,
dBFS or FS.

## Public CORE API and persistence

Example calls:

    ::GX::levelScaleSet graph_id y  [dict create scale dB quantity_kind amplitude amplitude_basis peak reference_value 1 reference_unit V zero_policy missing]
    ::GX::levelScaleSet graph_id y2 [dict create scale dB quantity_kind power reference_value 1 reference_unit W zero_policy missing]
    ::GX::levelScaleGet graph_id y

The y axis is Y1, y2 is Y2, and z is a 3D Z axis (since 0.9.7.12). Manifest Format 2 stores
[level_scale.<graph_id>.<axis>]; the same sections are emitted in standard
module runtime configuration. The Level scales control in Axes/Grid edits
the applicable axes independently. Cache-only rerender reads current runtime state.
Axis limits and steps are expressed in final displayed level values.

Fields: scale = linear, dB, dBFS or FS; quantity_kind = amplitude or power;
amplitude_basis = peak or rms for amplitude; reference_value = finite positive
number; reference_unit = explicit compatible physical unit; zero_policy =
missing or negative_infinity. dBFS and FS interpret the reference as full-scale.
The user declares whether an amplitude and its full-scale use peak or RMS;
CORE never guesses or converts between those bases. All series sharing one
axis use the same scale, quantity kind and reference. Y1, Y2 and Z can differ.

## Numerical convention

Input x and reference r are converted to the same compatible physical unit
before the level transform:

| Scale | Amplitude | Power |
| --- | --- | --- |
| linear | x | x |
| dB | 20 log10(abs(x)/r) | 10 log10(x/r) |
| dBFS | 20 log10(abs(x)/r_fullscale) | 10 log10(x/r_fullscale) |
| FS | signed x/r_fullscale | nonnegative x/r_fullscale |

A missing source unit, incompatible reference, nonpositive/nonfinite
reference, or attempted logarithmic transformation of already-level-valued
dB, dBFS or FS data is an error. No full-scale value or amplitude/power kind
is inferred.

For logarithmic scales, zero becomes NaN (missing) or -Inf according to
zero_policy. Negative amplitude uses its absolute magnitude in dB/dBFS,
so the displayed value loses sign; signed FS retains sign. Negative power
is invalid and becomes NaN for dB, dBFS and FS. NaN, positive infinity
and negative infinity samples become NaN for every non-linear transform.
Ordinary linear passes values through unchanged. Rendering may omit
nonfinite points.

The axis label includes scale, reference and peak/RMS basis, for example
Voltage [V] (dBFS re 2 V peak). Dataset arrays and Unit Registry
definitions are not rewritten.

## Plot metadata and selection

The plot geometry sidecar marks transformed axes with
y_transform=level_scale_v1 and records scale, quantity kind, basis,
reference and zero policy. Historic affine inverse fields are invalid
for a level-transformed Y axis. Dataset Selection API rejects Y rectangle
conversion on these axes until a signed/unsigned inverse selection
contract is provided. X-only selection remains valid.

plot.dataset calls the shared CORE transform after ordinary unit conversion;
it contains no local level formulas. Generic Scientific Analysis 2D
line/scatter/bar plots use the same helper.

## GX-TXT 0.9.7.11 plot variants

When a graph opts into Plot Module variants, each variant has separate y and y2 Level Scale dictionaries. The GUI resolves its selected artifact to the internal graph_id.variant_id state key; the variant runtime projects that state back to the declared graph_id sections expected by renderers. The base keeps its original graph_id key and default linear behavior. Both axes, references and zero policies persist independently for each variant. A Level Scale does not change the dataset.


## GX-TXT 0.9.7.12 Z extension

`levelScaleSet` and `levelScaleGet` accept `z` in addition to `y`
and `y2`. Manifest and runtime use `[level_scale.<graph_id>.z]`.
The Axes/Grid Level scales editor shows Z for 3D graphs. Plot variants
keep separate Z dictionaries; their runtime projects the selected
variant's Z state onto the declared graph ID.

3D renderers use the same `gxtxt_level_scale_config` and
`gxtxt_level_scale_apply` functions as Y1/Y2. They first apply ordinary
display-unit conversion, then transform Z only for presentation. Scientific
prepared Z and render caches stay linear. Changing the Z scale can therefore
rerender from a valid cache. Autoscale, explicit Z range and tick overrides
operate on displayed values. A transformed Z label includes scale, explicit
reference and peak/RMS basis. Plot metadata records `z_transform` and
`z_level_*`; affine inverse fields do not describe a nonlinear Z transform.

This extension does not define a separate Color Level Scale. A producer
must publish linear canonical magnitude for dBFS display; CORE does not
infer full-scale or quantity kind. Producer-computed runtime references
needed for dBc remain future work.

## Script Bridge operations (GX-TXT dev-037)

`set` accepts the public Level Scale field dictionary and validates it in CORE. `get` returns the framework-owned presentation dictionary, including the default linear state when no override exists. The state persists in the Session Manifest; use the exact graph or Variant state key and axis `y`, `y2`, or `z`. The Bridge performs no level conversion itself. Both Octave/MATLAB and Python call these names through `gxtxt_api_call(API_ID, operation, arguments)`. Arguments are positional and are passed to the named public Tcl procedure.

| Script operation | Public Tcl mapping | Positional arguments | Result |
| --- | --- | --- | --- |
| `get` | `::GX::levelScaleGet` | `graph_id`, `axis` | level scale struct |
| `set` | `::GX::levelScaleSet` | `graph_id`, `axis`, `fields` | level scale struct |

The Level Scale dialog remains host-only. Nested Tcl dictionaries and lists are converted recursively for script clients.
