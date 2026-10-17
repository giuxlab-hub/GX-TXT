# Calibrated curve digitization

Generate a new Session with **Calibrated Curve Digitization**. It contains an
original synthetic 100×100 RGB image and four exact reference points. No analysis
has been run. The generator requires Python's standard library and public Session
formats; it does not depend on Curve Digitizer or any analysis implementation.

Open `digitizer.calibration.image` in Curve Digitizer. Calibrate the rectangle:
bottom-left pixel (10,90), bottom-right (90,90), top-left (10,10), top-right (90,10).
Set linear Time from 0 to 8 s and linear Voltage from −2 to 2 V. Image Y increases
downward. The independent mapping is x=(pixel_x−10)/10 and y=(50−pixel_y)/20.

Digitize the blue crosses in the following order; preserve this order when
publishing. The reference Dataset is `digitizer.calibration.points`.

| Point | Pixel X | Pixel Y | Time (s) | Voltage (V) |
|---|---:|---:|---:|---:|
| point-1 | 30 | 70 | 2 | −1 |
| point-2 | 60 | 40 | 5 | 0.5 |
| point-3 | 75 | 65 | 6.5 | −0.75 |
| point-4 | 40 | 25 | 3 | 1.25 |

For fixed calibration and independent rectangular quantization cells of full
width 1 pixel horizontally and 2 pixels vertically, the standard uncertainties are
0.02886751345948129 s and0.02886751345948129 V, with zero cross covariance.
These are analytical references, not digitization precision inferred from the
screen. Review the assumptions before publication. Compare an explicit physical
override of 0.3 s and 0.7 V, with its stated rationale. Shared uncertain calibration
corners introduce correlations and must not be presented as independent sigmas.

Negative exercises: coincident calibration corners, a negative quantization
width, changed point order after review, and shared calibration passed as
independent measurement errors must be rejected. Retain the original image and
the exact point identities in any derived Dataset. Open the published result in
Fitter and inspect its units and retained uncertainty provenance.

`reference/calibration_truth.json` records axes, order, assumptions, exact pixel
and PNG hashes, analytical references and error cases. Its role is independent
verification; it is not a source of computed results for scientific modules.
There is no random seed because all coordinates are fixed. All sources and
synthetic assets are GPL-3.0-or-later.

For an existing installation whose Numerical Examples library is already stored
in user data, import `gxtxt_calibrated_digitizer_1.0.0.zip` into a library using
the Session Generator Library Manager. Existing libraries are preserved; importing
the standalone package makes this generator available without replacing them.
