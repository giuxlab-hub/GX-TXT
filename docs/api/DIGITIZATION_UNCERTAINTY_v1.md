# Pixel and calibration uncertainty

SPDX-License-Identifier: GPL-3.0-or-later

`NUMERIC_API_v1/digitization_uncertainty(linearization, specification)` propagates
independent point-local errors and shared calibration inputs. The public CORE
operations `digitization_interpretation(summary, context)`,
`digitization_fit_plan(meaning, kind, orientation)` and
`digitization_report(meaning)` own their scientific meaning. They are available
through the existing Python/Octave `gxtxt_api_call` entry point.

## Physical mapping

`gxtxt.digitization_linearization.v1` contains original `coordinates` (N×2),
`point_jacobian` (2N×2), `calibration_jacobian` (2N×M), two `coordinate_units`,
and M `calibration_ids`/`calibration_units`. Rows interleave X,Y for each original
point. `mapping`, `jacobian_method` and `condition_number` identify the producer.
N is1–4096 and M is1–32. All arrays must be finite; integer inputs outside the
exact binary64 range require an explicit conversion before use.

The existing Digitizer calibration owner supplies analytic sensitivities of its
four-point projective map and declared linear/logarithmic axes. Differentiating
the original homography equations preserves the same calibration. Its twelve
shared inputs are corner x,y in bottom-left, bottom-right, top-left, top-right
order, then physical X minimum/maximum and Y minimum/maximum. Reversed axes
retain their physical derivative signs. No recalibration or point mutation is
performed by linearization.

## Declared uncertainty model

For `mode=pixel_calibration`, require `pixel_distribution`, `pixel_scale` (two
positive values), `calibration_standard_uncertainty` (M nonnegative values) and
an explicit `rationale`. `rectangular_full_width` interprets each pixel scale as
the full width of a uniform error interval; standard uncertainty is width/√12.
`normal_standard_uncertainty` takes the two values as stated normal standard
uncertainties. Calibration inputs are supplied standard uncertainties and are
declared mutually independent inputs shared by all points; no probability
coverage is inferred for them. A zero value holds that input fixed.

`mode=physical_override` requires positive `override_standard_uncertainty`
(one X/Y pair or N×2) and a rationale. It replaces the error model with explicitly
declared independent physical uncertainties. Mixing override and pixel/calibration
fields is refused. The original coordinate mapping identity remains retained.

The existing `propagate_uncertainty` numerical owner applies first-order Jacobian
covariance propagation. Distribution assumptions and covariance terms matter;
pixel size alone is insufficient. This follows the principles in
[NIST TN1297 Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty).
Large nonlinear effects require a different validated uncertainty model; these
outputs make no confidence-interval or coverage-probability claim.

## Retained covariance and fitting

`gxtxt.digitization_uncertainty.v1` retains physical standard uncertainties,
point-local standard uncertainties, covariance blocks `(variance_X, covariance_XY,
variance_Y)`, independent factors, shared calibration factors, the complete
declaration and source/state SHA256 identities. The factors preserve cross-point
covariance without quadratic storage. The hash guards integrity, not hostile
authenticity. Declared boolean flags normalize across the existing scalar transport.

`digitization_covariance(state, axis)` materializes full covariance for `x`, `y`
or interleaved `xy`, bounded to512 original points. It uses the same propagation
owner and refuses changed retained factors. Original row order is preserved.

CORE fit plans require `orientation=y_of_x|x_of_y` and one of:

- `sigma`: response-only marginal sigma; unavailable with shared calibration.
- `sigma_xy`: actual diagonal XY ODR; unavailable with shared calibration or
  within-point XY correlation.
- `full_response_covariance`: full selected-axis covariance for a shared GLS
  consumer; predictor uncertainty is still ignored by this response-only model.

The correlation flag uses an explicit64ε binary64 roundoff threshold. Meaning,
qualifications, optional source-document/image/point-ID hash bindings and column
units survive public CORE validation and both typed Script languages. Independent
weighting must not be inferred merely because marginal sigma columns exist.
Publication preserves these scientific distinctions; a reviewed override is a
new declared error model, not an unreported omission of calibration uncertainty.

## Digitizer and Fitter consumers

The Digitizer configuration keeps an additive `uncertainty` declaration; absent
means disabled. The real Publish dialog saves/reviews it through the existing
calibration owner, CORE binary transport and Numeric operation. Review is tied
to the exact saved configuration SHA and current source image. Publication reuses
that captured result and refuses changed coordinates, units or original point
IDs. Existing six-field publication calls remain compatible; current publication
also retains `point_id`. Scientific identities x/y/curve_id/point_index are stable.

`CURVE_DIGITIZER_COMPANION_API_v1` exposes these Script operations in Python and
Octave through the standard `gxtxt_api_call`:

- `uncertainty_report(document_id, document_sha256)` reviews current saved state
  and returns the common qualified report. Matching reviews reuse the capture.
- `publication_uncertainty(dataset_id)` returns availability, typed common CORE
  `meaning`, exact Dataset/point counts and source hash, and inert `binding_utf8`.
- `publish_covariance(dataset_id, output_dataset_id, axis)` publishes original-row
  X or Y response covariance through canonical managed HDF5. It uses retained
  numerical factors, with no recalibration or fit. Full matrices are bounded to
  512 points. Squared units must be validated by the existing Unit Registry.

Published uncertainty metadata binds owned calibration JSON, point-ID order,
Numerical MAT state, physical columns and CORE interpretation resources to the
exact Dataset bytes. Retirement of a configuration preserves resources referenced
by published Datasets. Historical accepted fits remain readable independently of
subsequent edits to the configuration. Hashes check integrity, not authentication.

Fitter captures the producer binding, calls public CORE eligibility and checks
physical axes/units/row identity. Shared calibration refuses independent sigma;
correlated XY refuses diagonal ODR. Full covariance reaches existing GLS for
linear/polynomial models with the correct physical response and absolute scale.
Accepted results, reports, recipes, Session reopen and real Script consumers
retain the same qualifications. A transformed coordinate source requires an
explicit propagated uncertainty contract. The sole preserved ordering transform
is reverse sequence with exact original row IDs.
