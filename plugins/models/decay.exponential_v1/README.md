# Exponential and multi-exponential decay

`decay.exponential_v1` evaluates `amplitude*exp(-x/tau)`. Amplitude has units
Y; positive lifetime tau has units X. Negative amplitude is allowed. Negative
predictor coordinates extrapolate growth and may overflow; the native evaluator
rejects nonfinite results.

Compose two or more independently identified decay cards using
`fit_model_compose`, optionally with `baseline.constant_v1`. They share the
existing optimizer, weight/ODR handling and CORE inference. Bind parameter
names explicitly to share a lifetime; use reviewed bounds to distinguish
fast and slow lifetimes. No hidden sorting renames physical parameters.

Equal or nearby lifetimes, short observation intervals and weak components can
make the decomposition unidentifiable. Multiple starts help explore solutions
but do not prove uniqueness. Amplitudes refer to the recorded predictor origin;
coordinate translations and the resulting physical formula remain explicit.
