# Digitization Quality 0.1.0 Manual

## Purpose

Digitization Quality helps locate problems in a Curve Digitalizer configuration without changing the authoritative scientific state.

## Calibration diagnostics

Version 0.1.0 reports:

- calibration completeness;
- finite and ordered axis ranges;
- linear/log scale-domain validity;
- four-point control-point separation;
- calibration quadrilateral area and convexity/self-intersection;
- control points outside reported image bounds when dimensions are available;
- homography solve matrix condition number;
- four-control-point reprojection RMS;
- source Image Dataset identity/SHA-256 integrity.

The homography condition number is explicitly reported as coordinate-scale dependent. The four-point reprojection RMS mainly checks transform consistency because a four-point homography is exactly constrained by four correspondences. Neither value is presented as a universal quality score.

## Workflow

1. Open a Session containing Curve Digitalizer configurations.
2. Open `Digitization Quality` from Viewers.
3. Select a configuration.
4. Read the diagnostics and inspect any warning/error in Curve Digitalizer.

The module is read-only. It never edits calibration or digitized points.

## Current limitations

Point-distribution, curve-shape, visual-overlay and assisted/manual diagnostics remain future TODO items.
