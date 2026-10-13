# analysis.xas.normalize

Dataset-native XAS pre-edge / edge-step normalization for GX-TXT.

The module accepts `spectrum.scientific` and `spectrum.family` and publishes a
derived spectrum or family. Reusable differentiation, smoothing, polynomial
fitting/evaluation and array arithmetic are performed only through the public
`NUMERIC_API_v1` Octave binding.

The source Dataset is never modified.

The standard Octave runner uses the framework-relative module path in GX-TXT 0.9.8.10.
