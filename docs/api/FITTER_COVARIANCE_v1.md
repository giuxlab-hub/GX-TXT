# Fitter observation covariance

A full covariance matrix describes both nonconstant observation variance and
correlations between response errors. Fitter supports it for canonical linear
and polynomial models in Y(X) or X(Y) orientation through public Numeric GLS.
See [GLS numerical and statistical semantics](GENERALIZED_LEAST_SQUARES_v1.md).

## Declare the source rows

The preview option `covariance` is a dictionary with these fields:

| Field | Meaning |
|---|---|
| dataset_id, variable_id | Canonical Dataset/Variable containing the covariance |
| source_dataset_id | Exact response Dataset to which both matrix axes belong |
| response_variable_id | Y Variable in Y(X), or X Variable in X(Y) |
| row_binding | Must be `original_source_rows` |
| covariance_semantics | `absolute` (default) or `relative_scale` |
| singular_policy | `reject` (default) or `exact_constraints` |

The covariance Variable must be an enabled rank2 float32/float64 N×N array in
managed-binary storage. N equals every original response Dataset row, before
filtering, finite-pair omission, selection or sequence reversal, and is 2..2048.
The declaration is scientific input: matrix dimensions alone do not establish
which observations it describes. Both axes are indexed with the same exact
zero-based source-row IDs. No covariance row is inferred from display samples.

Response and covariance units must be declared, and covariance values must already
be in squared response units with scale 1. Convert prefixes upstream explicitly.
Translations preserve covariance. Smoothing, estimated-baseline subtraction,
logarithmic responses and other unpropagated transforms are rejected. Independent
sigma, both-axis sigma and relative precision are mutually exclusive with GLS.

`noise_model` is `unspecified`, `correlated_gaussian_known_covariance` for absolute
covariance, or `correlated_gaussian_estimated_scale` for relative covariance.
Choosing a Gaussian label does not supply a covariance matrix. Marginal intervals
reuse CORE's public parameter inference contract. Unavailable or deterministic
uncertainty stays explicit. Independent-error bootstrap/influence and response
bands are refused; no future-observation covariance is invented. Whitened residual
sequence diagnostics retain their fitting and ordering qualifications.

## Retain, replay and reuse

The normal preview result retains `covariance_binding` and `covariance_resource`.
The binding captures response identity/units, original count, covariance Dataset
content/schema identity, dtype, source/selected matrix hashes and exact training-row
hash. The selected matrix is an immutable Document resource in float64 column-major
order. Common training/evaluation statistical provenance keeps the same binding;
accepted fits and published fit Datasets preserve those resources and semantics.

Model queries, independent evaluation export, parameter reports and Workbench
transfer consume the existing retained model. They do not reload covariance or
refit observations. Exact rerun recipes retain the separate covariance Dataset
identity and refuse changed/missing covariance evidence. Templates do not silently
apply an observation-specific matrix to a different source. Declare a new binding
for a different scientific population.

In Python or Octave, capture/validate/run the same public Fitter recipe operations
used by other fits, with `covariance` inside `fit.options`. A captured recipe can
be exported as a real Script Job through the normal Python/Octave rerun commands.
For direct array-based scientific jobs, use Numeric `generalized_least_squares`
or `polynomial_gls` and the common CORE `from_numeric` adapter. No module-private
statistics or alternate transport is required.

The GUI exposes **Fit → Correlated observation covariance…** and
**Results → Full covariance fit details…**. Settings persist with their exact
source in the Session Workspace. Accepted results retain their captured settings;
changing the current covariance declaration requires a new preview before acceptance.
