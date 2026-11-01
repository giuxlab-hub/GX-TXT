# cal4/cal5/cal6 v6 point-cloud reference

This file records the independent Python reference check of the v6 point-cloud estimator. It is not a claim that Octave was executed in the build container.

With the current default `fit_output_grid_points=200`, every family receives 200 fit-ready points, independently of how many raw points were digitized.

Approximate Python-reference RMS components:

| Family | Raw points total | Statistical grid | Fit grid | RMS within | RMS between | RMS total |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 369 | 360 | 200 | 0.01250 | 0.01868 | 0.02248 |
| 25 | 630 | 626 | 200 | 0.03548 | 0.04735 | 0.05917 |
| 50 | 531 | 522 | 200 | 0.02741 | 0.03707 | 0.04610 |
| 100 | 579 | 561 | 200 | 0.03556 | 0.03875 | 0.05260 |
| 150 | 846 | 825 | 200 | 0.03188 | 0.04442 | 0.05468 |
| 200 | 621 | 606 | 200 | 0.04634 | 0.05374 | 0.07096 |
| 300 | 774 | 722 | 200 | 0.29642 | 0.25860 | 0.39337 |

The comparatively large family-300 dispersion is present in the supplied point cloud and should be inspected in the real Octave plots rather than suppressed algorithmically.
