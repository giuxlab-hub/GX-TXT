# example.ir_chain_metrics_v1

SPDX-License-Identifier: GPL-3.0-or-later

Reference definition for **Scientific Analysis Definition API v1**.

It consumes the `analog_chain_comparison.csv` table produced by `gxtxt.ir_waveform` v3.3 and deliberately recomputes generic quantities through framework operations:

- `relative_amplitude_api`: `compare` against the row whose `trace` is `VIR`;
- `margin_fraction`: safe declarative `expression` (`margin / carrier_amplitude`);
- `margin_normalized`: framework `normalize(maxabs)`.

The definition contains no Octave handler and no IR-specific algorithm. Its purpose is to prove that a plugin can describe a data-flow and reuse framework code.

Expected source columns:

```text
trace
carrier_amplitude_V
threshold_V
median_margin_V
```

The example module `analysis.definition_demo` selects this definition through the new descriptor field type `analysis_definition`.
