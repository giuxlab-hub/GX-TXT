# Cross-Spectral Transfer Function Session Generator

Generate a deterministic 49,152-row paired-signal Session for `analysis.cross_spectral_transfer`. The known transfer gain is 2.5 V/V at the three generated tones. Version 1.0.2 creates a canonical Dataset, persisted Analysis bindings and a 12-member Temporal Window Set directly from its own source definitions, with cross-spectral generator provenance in the Dataset registry. The Session is ready for normal Analysis, save/reopen/rerun and HTML export. Generation itself needs only Python's standard library.
