# analysis.envelope_spectrum

GX-TXT analysis plugin for analytic-signal envelope demodulation and envelope-spectrum analysis.

Version 1.1.0 consumes the public `NUMERIC_API_v1` service for reusable FFT/IFFT, analytic-signal construction, frequency grids, one-sided transform selection, detrending, analysis windows, grid diagnostics and descriptive statistics. Scientific envelope-demodulation semantics remain in this module.

The module publishes both the time-domain envelope and the envelope spectrum as canonical Datasets and creates persistent scientific graphs through `plot.dataset`; it contains no private scientific result renderer.

Typical uses include amplitude-modulated carriers, impulsive/resonant vibration signals, bearing/fault-frequency demonstrations and other cases where periodic modulation is more visible in the signal envelope than in the original carrier spectrum.

A deterministic student Session Generator is bundled in `session_generators/`. See `MANUAL.md` for the scientific model, workflow and limitations.

SPDX-License-Identifier: GPL-3.0-or-later
