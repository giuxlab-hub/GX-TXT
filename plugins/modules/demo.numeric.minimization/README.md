# demo.numeric.minimization

`demo.numeric.minimization` 1.0.2 is an external GX-TXT demonstration/reference module for the public one-dimensional minimization architecture.

It consumes a normal Canonical Dataset through Analysis Source bindings, evaluates the selected curve through public `NUMERIC_API_v1 dataset_interpolate`, supplies that public Dataset-backed callback to public `NUMERIC_API_v1 minimize_1d`, publishes the minimum through Dataset Publication API v2, writes a report, and creates a `plot.dataset` graph with the detected minimum marker.

The module contains no private interpolation or minimization algorithm. It does not call GNU Octave `fminbnd` directly.

## Quick workflow

1. Install `demo.numeric.minimization_1.0.2.zip` through GX-TXT Plugin Install.
2. Import the bundled Session Generator into **GX-TXT Numerical Examples** if it is not already present.
3. Generate **Mathematics → 1D Minimization**.
4. Import `raw/minimization_1d.csv` through normal Acquisition as `table.generic`.
5. Enable `demo.numeric.minimization`, bind `x` and `f`, choose bounds, and Run.

The deterministic example uses `f(x)=(x-1.75)^2+2`, whose exact minimum is `x=1.75`, `f=2`.

See `MANUAL.md` for current behavior, dependencies and verification.

SPDX-License-Identifier: GPL-3.0-or-later
