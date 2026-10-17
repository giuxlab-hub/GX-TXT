# Bayesian inference availability

The bundled Numeric and Fitter providers do not implement Bayesian MCMC.
There is no public sampler operation, Bayesian Fitter model card or registered
posterior statistical-result interpretation. **Feature status: NOT_IMPLEMENTED.**
Sampler numerical tests are **NOT RUN — FEATURE UNAVAILABLE**.

The current interface supplies no prior declarations, sampling chains,
burn-in/adaptation record, convergence/R-hat/effective-sample-size diagnostics,
posterior summaries or credible intervals. No MCMC backend is selected by a
bundled public provider. Installing an external Python or Octave library does
not add a GX-TXT operation, validate its diagnostics or change this feature status.

In an initialized GX-TXT Tcl environment, inspect the public provider directly:

```tcl
::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
::GX::NumericAPIv1::supports bayesian_mcmc
# Returns 0.
::GX::NumericAPIv1::listOperations
::GX::NumericAPIv1::listFoundationOperations
```

The statistical model catalog is available through
`::GX::StatisticsV1::models`, and Fitter cards through `modelCards` / the Script
operation `model_cards`. An unsupported capability or operation request is
rejected explicitly. The availability audit checks these real registrations;
an audit PASS means that the declarations are truthful, not that a sampler ran.

Existing local covariance intervals and parameter bootstrap retain their own
frequentist assumptions and eligibility rules. Do not rename them credible
intervals or describe parameter draws as a posterior. See the
[parameter-bootstrap contract](PARAMETER_BOOTSTRAP_v1.md) and
[common fitting errors guide](../guides/COMMON_FITTING_ERRORS.md).
