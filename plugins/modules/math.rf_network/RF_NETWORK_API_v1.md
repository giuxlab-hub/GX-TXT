# RF_NETWORK_API_v1

Provider: `math.rf_network` 1.2.0. API ID/version: `RF_NETWORK_API_v1`/1. The API analyzes measured or imported complex network data; it does not simulate circuits. GNU Octave linear algebra is the current backend. Every operation runs serially.

## Bindings and input contract

- GNU Octave: `gxtxt_rf_network_v1(family,action,a,b,c,options)`.
- Tcl: activate `math.rf_network`/`RF_NETWORK_API_v1`, then call `::GX::RFNetworkAPIv1::call family action a b c ?options?`.
- Registered Octave/Python scripts: `gxtxt_api_require('RF_NETWORK_API_v1@1:math.rf_network')` and `gxtxt_api_call('RF_NETWORK_API_v1','family.action',args)`.
- `apiInfo`, `listOperations`, and `operationMetadata` are public Tcl discovery functions; `api/operations_v1.tsv` and Script Bridge metadata are machine-readable.

Tcl/Bridge operands use the typed-node transport described in `SIGNAL_API_v1`: arrays declare shape and column-major real/optional imaginary values; structs, cells, text and empty nodes are explicit. Octave accepts ordinary arrays/structs. Outputs split complex arrays into `value_real`/`value_imaginary`. Every S/Z/Y matrix is square, and ABCD is 2 by 2. Port indices are one-based. A frequency sweep has a strictly increasing frequency axis in Hz and its first data dimension matches the frequency count. Reference impedance is explicit in ohms: scalar, per-port vector, or per-frequency/per-port sweep values. Complex values must have positive real part and an explicit `wave_convention=power|traveling`; the definition controls S/Z/Y normalization.

## Operation inventory

| Family | Action | Inputs and result |
|---|---|---|
| `convert` | `representation` | Matrix `a`, reference `b`, options `source=s|z|y|abcd|t|h`, `target=s|z|y|abcd|t|h`. S/Z/Y conversions use the declared power or traveling-wave convention; positive real references preserve the prior power-wave behavior. ABCD uses `[V1; I1] = [A B; C D][V2; -I2]`. Ideal through S↔ABCD uses direct formulas. Singular conversions fail. |
| `convert` | `renormalize` | S matrix, explicit `old_z0` and `new_z0`; transformation proceeds through Z and reports singular/conditioning errors. |
| `compose` | `cascade`, `deembed_left`, `deembed_right`, `deembed_both` | ABCD matrices; composition multiplies two-port transmission matrices, de-embedding solves linear matrix equations. |
| `compose` | `series`, `shunt`, `port_extension` | Series adds Z matrices, shunt adds Y matrices. Port extension applies explicit port delays at an explicit frequency to a two-port S matrix. |
| `metric` | `return_loss`, `insertion_loss`, `isolation`, `vswr`, `reflection`, `transmission`, `impedance`, `admittance`, `transducer_gain` | S matrix, optional reference impedance, declared ports/source-load reflection coefficients. Losses are positive dB for attenuating paths; transducer gain is linear power gain. |
| `metric` | `group_delay`, `phase_delay` | Selected complex response vector and increasing frequency vector; result is seconds. |
| `quality` | `reciprocity`, `passivity`, `losslessness`, `stability`, `causality` | Frobenius or power-gain residuals and explicit tolerance. Two-port stability returns Rollet K, μ, |Δ| and available/stable gain where defined. |
| `calibration` | `one_port_solve`, `one_port_apply` | Three declared standards solve the one-port directivity/source-match/reflection-tracking error terms, then apply them to measured reflection. Degenerate standards fail. |
| `sweep` | `describe`, `convert`, `renormalize`, `group_delay`, `mixed_mode` | Complex frequency sweep. Conversion and renormalization process each frequency with scalar, per-port or frequency-by-port reference impedance. Group delay selects one response with explicit port indices. `mixed_mode` uses 4-port pair order (1,2) and (3,4), with differential/common transforms. |

Conditioning uses `condition_limit` (default `1e12`); matrix solves avoid explicit inverse. Incompatible dimensions, singular denominators, nonfinite values, unphysical VSWR and invalid reference impedances produce `GXTXT:RF:*` errors. The S↔ABCD direct formula uses one common reference where the direct formula is valid. Per-port references are accepted for S/Z/Y; asymmetric per-port ABCD conversions pass through Z and require its conversion to be nonsingular. Passivity checks use the largest eigenvalue of `S'*S`; an active network can be valid but will fail that check. Group delay is a numerical derivative of unwrapped phase and is sensitive to sparse/noisy frequency samples.

## Examples

```octave
S=[0 1;1 0];
r=gxtxt_rf_network_v1('convert','representation',S,50,[],struct('source','s','target','abcd'));
assert(norm(r.value_real-eye(2))<1e-12);
```

```python
from gxtxt import gxtxt_api_require, gxtxt_api_call
gxtxt_api_require('RF_NETWORK_API_v1@1:math.rf_network+convert')
S={'kind':'array','shape':[2,2],'real':[0,1,1,0]}
z0={'kind':'array','shape':[1,1],'real':[50]}
opts={'kind':'struct','fields':{'source':{'kind':'text','value':'s'},'target':{'kind':'text','value':'abcd'}}}
r=gxtxt_api_call('RF_NETWORK_API_v1','convert.representation',[S,z0,{'kind':'empty'},opts])
```

```octave
gxtxt_api_require('RF_NETWORK_API_v1@1:math.rf_network+convert');
S=struct('kind','array','shape',[2 2],'real',[0 1 1 0]);
z0=struct('kind','array','shape',[1 1],'real',50);
opts=struct('kind','struct','fields',struct('source',struct('kind','text','value','s'),'target',struct('kind','text','value','abcd')));
r=gxtxt_api_call('RF_NETWORK_API_v1','convert.representation',{S,z0,struct('kind','empty'),opts});
```

Network Dataset consumers should use existing Canonical Dataset, Variable Schema, Dataset Metadata and Publication APIs. Stable frequency, real and imaginary variable IDs plus declared Hz/ohm units and reference-impedance metadata are required. The shared details are in `docs/api/SCIENTIFIC_FIELD_AND_SWEEP_DATASET_CONTRACT_v1.md`; this provider does not introduce a separate Dataset store.

## Touchstone acquisition

`acq.touchstone` is a normal acquisition module for Touchstone v1 RI/MA/DB S-parameter files from `.s1p` through `.s32p`. It publishes one canonical `spectrum.table` Dataset with `frequency_Hz` and stable `sij_real`/`sij_imag` columns, source SHA-256, declared port count and reference impedance. Touchstone 2 keyword files are diagnosed as unsupported. The importer does not perform network conversion during parsing.
# Guided-client metadata

`operationMetadata(id)` also returns `arguments`, `argument_descriptors`,
`signature`, `worksheet_example`, `result_fields`, and `unit_behavior`.
These fields are derived from the provider-owned operation and family
contracts. They let a Worksheet or other guided client display the public
call's inputs and unit/result expectations without parsing implementation
code. The existing `call(family, action, a, b, c, options)` contract is
unchanged.
