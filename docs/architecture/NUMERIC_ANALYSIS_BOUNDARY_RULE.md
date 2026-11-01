# Mandatory Architecture Rule: `math.numeric` vs `analysis.*`

SPDX-License-Identifier: GPL-3.0-or-later

This document is **normative and mandatory** for GX-TXT development.

For dev097, the common statistical authority additionally governs every statistical
result: public Numeric owns calculations, and CORE
`STATISTICAL_RESULT_SEMANTICS_API_v1` owns definitions, units, applicability,
availability and report formatting. This takes precedence over historical
examples below that leave THD, spectral moments, Welch interpretation or other
statistical meaning inside an Analysis module. Modules retain workflow choices,
source selection, public API configuration, Dataset publication and graph setup;
they consume captured CORE results without recalculating them. Distinct existing
scientific estimators retain separate registered identities and assumptions.

It defines the ownership boundary between the public numerical service `math.numeric` / `NUMERIC_API` and scientific/domain modules such as `analysis.*`, `curve.*`, `curvefit.*`, `model.*`, and other consumers of reusable mathematics.

## 1. Mandatory separation

The required architecture is:

```text
Canonical Dataset / Analysis Source
        ↓
scientific or domain module
        ↓
domain-specific workflow and scientific semantics
        ↓
public math.numeric / NUMERIC_API
        ↓
generic reusable mathematical primitive
```

`math.numeric` owns **reusable mathematics**.

A scientific/domain module owns **the meaning and workflow of an analysis**.

The fact that both layers may operate on the same curve, vector, spectrum, family, or Dataset does not make them duplicates. Their responsibilities are different.

## 2. What belongs in `math.numeric`

A mathematical operation belongs in `math.numeric` when it is reusable without knowing the scientific meaning of the data.

Examples include, when required by real consumers:

- interpolation and resampling;
- splines and PCHIP;
- numerical integration and cumulative integration;
- differentiation;
- grids and ranges;
- generic reductions and descriptive statistics;
- quantiles and weighted quantiles;
- cumulative sums and other reusable vector reductions;
- weighted statistics;
- covariance/correlation primitives;
- linear and weighted least squares;
- regression;
- polynomial fitting/evaluation;
- nonlinear least squares;
- generic optimization and root finding;
- smoothing and moving statistics;
- Savitzky-Golay and generic filters;
- peak and baseline primitives;
- uncertainty propagation;
- FFT/IFFT;
- frequency-grid helpers;
- one-sided/two-sided transform helpers;
- generic window generation;
- generic detrending;
- analytic-signal construction;
- other reusable mathematical primitives demonstrated by real GX-TXT consumers.

The backend may currently use GNU Octave. Consumer architecture must depend on `NUMERIC_API` capabilities, not on direct Octave function names or package paths.

## 3. What belongs in `analysis.*` and other scientific/domain modules

The scientific/domain module retains the logic that gives mathematical operations their meaning.

Examples include:

- choosing which variables/Datasets participate in the analysis;
- validating scientific compatibility, units, roles, or provenance;
- defining the analysis-specific workflow;
- interpreting an FFT as a particular spectrum;
- Welch PSD semantics and configuration;
- spectral centroid, flatness, crest and entropy definitions;
- harmonic/fundamental selection and THD semantics;
- cepstrum interpretation;
- envelope-analysis workflow;
- spectroscopy workflow and chemical interpretation;
- IR protocol decoding/identification;
- curve-family model equations and parameter semantics;
- replicate compatibility, consensus rules and provenance;
- analysis-specific warnings and acceptance criteria;
- Dataset Publication choices;
- report generation;
- graph selection and scientific presentation through shared graph APIs.

A domain module may compose many `NUMERIC_API` operations. It must not reimplement the generic primitive itself.

## 4. Absolute rule for missing functionality

A consumer module must **never create a private generic mathematical implementation merely because the public API is incomplete**.

Required sequence:

```text
consumer needs a generic mathematical operation
        ↓
is the capability already public in NUMERIC_API?
        yes → use it
        no
        ↓
extend math.numeric / NUMERIC_API with the smallest generic capability
        ↓
add focused service-level tests/documentation
        ↓
consume the new public capability from the scientific module
```

Forbidden sequence:

```text
missing NUMERIC_API capability
        ↓
private fft / mean / interpolation / fitting / cumsum / quantile / optimizer / filter implementation inside analysis.*
```

Historical modules containing direct numerical implementations are migration targets, not architectural precedent.

## 5. Practical classification test

Before adding mathematical code to a production consumer, classify it:

```text
A. generic primitive already provided by NUMERIC_API
   → use NUMERIC_API

B. generic primitive missing from NUMERIC_API
   → extend math.numeric first, then use NUMERIC_API

C. genuinely domain-specific scientific algorithm/semantics
   → keep in the scientific/domain module

D. implementation detail inside math.numeric itself
   → allowed in math.numeric
```

A useful heuristic is:

> If the operation still has the same mathematical meaning after all domain labels are removed from the input, it probably belongs in `math.numeric`.

This heuristic does not override scientific judgment, but ambiguous generic code must be reviewed before being retained locally.

## 6. Examples

### Curve operations

```text
interpolate Y(X)             → math.numeric
numerical derivative         → math.numeric
Savitzky-Golay smoothing     → math.numeric
nonlinear least squares      → math.numeric
```

```text
compare replicate digitizations
  compatibility/provenance   → curve.replicate_analysis
  interpolation              → math.numeric
  consensus statistics       → math.numeric
  scientific output meaning  → curve.replicate_analysis
```

### Spectral features

```text
mean / maximum / sum         → math.numeric
uniform-grid diagnostics     → math.numeric
weighted quantiles           → math.numeric
cumulative sum               → math.numeric
```

```text
spectral centroid definition
spectral flatness definition
spectral crest definition
normalized spectral entropy
rolloff/occupied-band meaning
input amplitude/power/PSD semantics
                              → analysis.spectral_features
```

## 7. Dataset and API rules

When a Dataset-aware `NUMERIC_API` operation exists, prefer it where appropriate. Otherwise obtain vectors through public Dataset/Analysis Source/Table Stream APIs and pass those vectors to the low-level public numerical operation.

Consumer modules must not:

- hard-code `plugins/modules/math.numeric` paths;
- source private `math.numeric` implementation files;
- call service worker internals;
- copy Octave implementations from `math.numeric`;
- depend on the physical installation location of the service.

Use the normal dependency/public-API discovery mechanism.

## 8. Graphics are a separate shared boundary

The numerical boundary does not replace the graphics boundary.

Normal scientific flow is:

```text
Dataset / Analysis Source
        ↓
analysis/domain semantics
        ↓
math.numeric / NUMERIC_API
        ↓
derived Dataset(s)
        ↓
plot.dataset / Graph Provider
```

A module can be numerically compliant and graphically non-compliant, or vice versa. Both shared-service rules must be satisfied.

## 9. Development requirement

Before creating or modifying a production scientific module, the implementer must:

1. read this document;
2. inspect current `math.numeric` / `NUMERIC_API` capabilities;
3. audit the module for duplicated generic mathematics;
4. extend the public numerical service first if a required generic primitive is missing;
5. keep only domain-specific scientific semantics in the consumer;
6. test the public numerical capability independently of the consumer;
7. test the packaged consumer against the public API discovery path.

This rule is binding for new development and for migration of historical modules.

## Automated ownership guard

Run `python3 tools/check_numeric_service_boundary.py` from the framework
root. It checks production analysis runtime `.m` calls against a deliberately
narrow map of generic operations already advertised by `NUMERIC_API_v1`.
The map links each call to the public capability that owns it. The
`math.numeric` provider is excluded because it implements that service;
acquisition parsing, GUI adapters and domain-specific formulas are outside
the rule. A justified domain use can be exempted by a preceding comment
`GXTXT_NUMERIC_DOMAIN_EXCEPTION: <reason>`. Review the reason with the source.
Extend the map when a new shared numerical capability becomes public. The
guard checks architecture placement; public numerical and real Session tests
still establish behavior.
