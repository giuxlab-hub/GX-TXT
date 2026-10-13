# GX-TXT `spectrum.table` Contract v1

SPDX-License-Identifier: GPL-3.0-or-later

`spectrum.table` is the first-class canonical contract for frequency-domain spectral tables.

It is registered by GX-TXT core and declares:

```text
spectrum.table -> table.generic
```

Therefore every consumer accepting `table.generic`, including the CORE `plot.dataset`, can consume a spectrum without special-case conversion. Consumers may also request `spectrum.table` explicitly when frequency-domain semantics are required.

Normative semantic expectation:

- at least one canonical independent variable represents frequency;
- its physical dimension is frequency and the canonical/source unit should normally be `Hz`;
- dependent variables may represent magnitude, power, phase, PSD or other spectral quantities and carry their own Unit/Dimension metadata;
- the contract does not prescribe a particular magnitude unit or FFT normalization.

Variable metadata remain authoritative. Consumers must not infer semantics from names such as `frequency_Hz` alone.
