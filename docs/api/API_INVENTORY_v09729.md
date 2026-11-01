# GX-TXT API inventory for 0.9.7.29

No public CORE API version changes in this release.

| API | Version | Status in 0.9.7.29 |
|---|---:|---|
| Canonical Dataset API | 1 and 2 | Retained |
| Dataset Variable Schema API | 2 and 3 | Retained |
| Dataset Publication API | 1 and 2 | Retained |
| Table Stream API | 1, 2 and 3 | Retained |
| Analysis Source Map API | 1 | Retained |
| Analysis Source Access Runtime | 2 | Retained |
| Graph Series API | 1 | Retained; authoritative plot.dataset 2D bindings |
| Plot Module API | 1 | Retained base/variant composite identity |
| Plot Region Selection API | 1 | Retained; topology/calibration diagnostics corrected |
| Dataset Selection API | 1 | Retained X-range producer identity |
| Multi-Y Axis Plot API | 1 | Retained |
| Graph Provider API | 1 | Retained |
| Viewer Provider API | 1 | Retained |
| PLOT_DATASET_API | 1 | Frozen entrypoint retained byte-identically |
| PLOT_DATASET_API | 2 | Supplied plot.dataset 2.1.4 implementation integrated |

The Region Selection metadata additions do not change its public version.
selection_supported keeps its existing meaning: selection is usable only when
both supported topology and calibrated raster geometry are present. The new
selection_topology_supported, selection_calibration_valid and
primary_axis_is_3d fields explain that result without changing graph identity
or selection semantics.
