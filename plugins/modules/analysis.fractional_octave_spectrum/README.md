# analysis.fractional_octave_spectrum 1.1.0

Dataset-native octave / fractional-octave spectral analysis for GX-TXT.

The module integrates a **linear PSD** into exact base-10 1/1, 1/3, or 1/6-octave bands and publishes band power, RMS and configurable-reference dB level as a canonical `spectrum.table`. The band-definition and PSD-bin-overlap logic remain domain-specific scientific workflow.

Scientific result graphs are persistent `plot.dataset` variants. Bars use the public `bar_x_bounds` capability so every rendered interval is bound to the published `lower_frequency` and `upper_frequency` variables rather than an approximate scalar width.

A deterministic student Session Generator is bundled in `session_generators/`. See `MANUAL.md`.
