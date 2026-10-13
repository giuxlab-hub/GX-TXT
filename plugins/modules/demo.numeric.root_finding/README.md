# demo.numeric.root_finding

`demo.numeric.root_finding` 1.0.2 is an external GX-TXT reference plugin for the public root-finding path available in GX-TXT 0.9.7.86.

The plugin does not implement a root solver, sign-change scanner, interpolation algorithm, or equation parser. Its numerical path is:

```text
Canonical Dataset X/Y
→ NUMERIC_API_v1 dataset_interpolate
→ Octave callback
→ NUMERIC_API_v1 root_find
→ Canonical root Dataset
→ PLOT_DATASET_API_v2 graph
```

The public `root_find` operation is callback-based and uses the `math.numeric` Octave binding. The Dataset-to-callback path is supplied by the public Dataset-aware interpolation operation. Root intervals are explicit user input; the plugin never scans a range to discover candidate brackets.

## Installation

Install `demo.numeric.root_finding_1.0.2.zip` with the normal GX-TXT Plugin Install interface/API. The package requires GX-TXT 0.9.7.86 or later because its automatic graph uses the public `standard_octave` bridge to `PLOT_DATASET_API_v2` introduced in 0.9.7.86.

A portable Session Generator package is bundled under `session_generators/` and is also distributed separately:

```text
gxtxt_numerical_examples_root_finding_1.0.0.zip
```

Import it into the existing `GX-TXT Numerical Examples` library. It adds:

```text
Mathematics → Root Finding
```

The generated Session contains `raw/root_finding.csv` with columns `x` and `f` for

```text
f(x) = (x + 2) * (x - 0.5) * (x - 3)
```

and analytical roots `-2`, `0.5`, `3`.

See `MANUAL.md` for the complete workflow and semantics.
