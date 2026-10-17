# Voigt peak

`peak.voigt_area_v1` evaluates `area*voigt_profile(x-center,sigma,gamma)`.
The normalized profile is `Re(w((x+i*gamma)/(sqrt(2)*sigma)))/(sigma*sqrt(2*pi))`.
`area` has units Y times X; center, sigma and gamma have units X. Sigma is a
Gaussian standard width; gamma is a Lorentzian HWHM. Neither is the total
Voigt FWHM. Negative area represents an inverted peak.

Sigma must be positive; gamma may be zero. The zero-sigma Lorentzian limit has
its own descriptor, `peak.lorentzian_height_v1`, with a different height
parameter. These scientific identities are never silently interchanged.
Overlapping peaks and the two widths can be poorly identified; inspect CORE
rank and covariance eligibility. Add an explicit independent baseline card.

The shared Numeric expression VM reuses Octave's complex `erfcx`, and supplies
analytic derivatives with stable asymptotic evaluation in the tails. All fits
use the same public Ceres path and CORE statistical interpretation. The frozen
composition records the model version, descriptor SHA, definition and units.

Reference: [SciPy Voigt definition](https://docs.scipy.org/doc/scipy/reference/generated/scipy.special.voigt_profile.html).
