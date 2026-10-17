## 1.2.4

Add saved uncertainty declarations, explicit review/override controls, stable
point IDs and exact calibration/image/row provenance on published sigma and
covariance. Reuse public Numeric/CORE and canonical managed full-covariance
publication. Expose real Python/Octave Companion consumers; preserve historical
configuration/publication and retired-owner resource compatibility.

## 1.2.3

Expose analytic calibration sensitivities from the existing homography/axis
owner for shared Numeric/CORE uncertainty propagation. Preserve original
calibration, point identities and Session configuration serialization.

## 1.2.20

- Resolve Session context and source image through public Session Inspection; preserve measured-versus-registered SHA diagnostics for stale-source reporting.

# Changelog

## 1.2.1

- Normalize LF and CRLF protocol requests at the Tcl pipe, including Windows BOOTSTRAP.
- Read host control messages while the Python/Tk viewer is idle and acknowledge GUI readiness separately from child process creation.
- Show a responsive startup window with a bounded bootstrap wait, and retain host/Python diagnostics in the current Session logs.
- Use the configured Python runtime and preserve command-list executable paths. No calibration, persistence or Dataset publication format changed.

## 1.2.0

- Added `CURVE_DIGITIZER_COMPANION_API_v1` for tightly coupled assistant modules without a second authoritative state model.
- Added stable configuration/curve context discovery and source Image Dataset integrity resolution through public GX-TXT APIs.
- Added guarded pixel-point commit that reuses the Curve Digitalizer calibration model and writes accepted points into the existing Interactive Document.
- Added document SHA-256 optimistic concurrency so an open Curve Digitalizer window cannot silently overwrite newer companion-module changes.

## 1.0.1

- Added a source-image preview confirmation dialog when selecting a new Image Dataset for a configuration.
- Prevented accidental binding to the wrong image by requiring explicit confirmation before the source association is persisted.
- Kept packaged GUI validation deterministic by auto-accepting the preview step only in the non-interactive regression scenario.

All notable changes to `viewer.curve_digitizer` are documented here.

## 1.0.0

- Initial GX-TXT-native release for GX-TXT 0.9.7.78.
- Reused the original Curve Digitizer homography/calibration model and interactive image canvas behavior where scientifically appropriate.
- Replaced standalone image-open, project-file, and CSV-export workflows with current GX-TXT Image Dataset selection, Session-persistent Interactive Documents, Dataset Metadata, and Dataset Publication API v2.
- Added named configurations with stable IDs, rename/duplicate/delete management, and support for multiple independent configurations per source Image Dataset.
- Added source byte integrity verification with SHA-256 and explicit missing/stale-source diagnostics.
- Added linear/log X/Y calibration, labels, units, semantic roles, calibration verification, curves, numerical curve families, point editing, undo/redo, zoom/pan, overlays, and darkest-pixel snapping.
- Added publication of independent curves as `table.generic` and numerical curve families as `curve_family.table` with stable variable IDs and preserved point order.
- Added same-owner deterministic republishing, output Dataset Metadata, Variable Schema enrichment, source Dataset lineage, and CSV artifact creation in the publication transaction.
- Added lazy Viewer Provider backend activation and interactive dependency preflight for Python/Tk/NumPy/Pillow.
- Added deterministic scientific, static host-independence, and real Xvfb/Tk integration tests.
