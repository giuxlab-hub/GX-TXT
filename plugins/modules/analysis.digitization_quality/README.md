# GX-TXT Digitization Quality

`analysis.digitization_quality` provides read-only diagnostics for Curve Digitalizer configurations.

Version `0.1.0` implements calibration diagnostics only. It reports axis validity, log-domain validity, four-point calibration geometry, homography matrix conditioning, four-control-point reprojection consistency and source Image Dataset integrity.

It does not modify calibration, curves or points and deliberately does not produce a universal quality score.

License: GNU GPL v3 or later.
