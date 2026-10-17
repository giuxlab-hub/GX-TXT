# Creative image, geometry and CAM foundation

This is a design boundary for future CAM work. It defines no executable CAM API,
postprocessor, toolpath generator, G-code output or machine-control capability.
The implemented image/geometry path ends at retained RGBA appearance, validated
closed profiles and existing native extrusion/export.

## Scientific source and coordinate chain

| Item | Existing authority | Meaning and required identity |
| --- | --- | --- |
| Original raster | Canonical Image Dataset or managed Document resource | Immutable pixels, SHA, actual dimensions, original provenance |
| ROI and image placement | Native2D image object and existing identity attributes | Source-pixel vertices, native validity, revision, image resource identity, calibrated similarity transform |
| Raster result | Existing supervised ImageMagick Job and managed result resource | Captured ROI/layers/blend/mask, tool/version/parameters, SHA and full rectangular RGBA output |
| Solid appearance | Existing Native3D object style and native planar texture assignment | Source geometry SHA and actual source triangle, object-local anchor, explicit UV/physical extent/rotation/flips |
| Closed profile | Existing retained Native2D definitions and Native3D profile | Declared length unit, captured orthonormal plane, ordered contours/holes and provenance |
| Extruded geometry | Existing Native3D kernel and destination Workbench History | Exact owned result, signed physical depth, area/volume/topology, complete export resources |

Image pixels acquire physical meaning only through an explicit calibration.
Decorative image placement can resize appearance independently and must retain
that distinction. A silhouette extracted from a photograph does not establish
unknown depth, material, scale, tolerances or machining feasibility.

## Proposed future records

These records describe requirements; they are not registered executable schemas.
All dimensional values need a Unit Registry quantity or an explicit compatible
unit. Existing Dataset/Document/resource identities and revision guards should
be reused rather than introducing a parallel project, geometry or Job store.

| Record | Required content | Validations before any future execution |
| --- | --- | --- |
| Machine | Explicit machine identity, axis topology, travel and supported operations | Declared units, finite ordered limits and known controller/postprocessor capability |
| Stock | Destination-owned solid, physical frame and material identity | Current geometry SHA, dimensions, orientation, nonempty volume and explicit workpiece origin |
| Tool | Tool identity, cutter geometry, diameter/length, holder envelope and compatible material | Positive physical dimensions, declared units, complete limits and actual machine compatibility |
| Setup | Stock, fixture, machine and work coordinate frame | Rigid right-handed frame, explicit source-to-work transform, retained calibration/provenance and finite offsets |
| Operation | Named strategy, exact source selection, target depth/region and chosen tool | Source revision/ownership, supported geometry, signed physical limits and no implicit unit conversion |
| Process settings | Explicit spindle speed, feed, step-over/step-down and clearance | Dimensionally correct quantities within recorded machine/tool limits; no guessed values from pixels |
| Simulation evidence | Input hashes, stock/tool/fixture states, method/version and reported limitations | Complete domain, explicit collision/remaining-stock availability and repeatable settings |
| Postprocessing request | Reviewed operation result, target machine/controller and actual postprocessor version | Explicit compatible dialect and reviewed coordinate/unit policy; no automatic machine delivery |

Simple future contour, pocket and drilling strategies are separate operations.
A 2D boundary is not a finished machining plan. Open, self-crossing, touching or
ambiguous profiles require correction or explicit rejection before any strategy
can consume them. Hole/material containment must come from the native profile
owner rather than a second polygon interpreter.

## Future execution boundary

A future implementation should use the existing supervised Jobs and immutable
I/O manifests for actual external computation. Preparation must capture source
owner/generation/revision/SHA, geometry resources, physical units, frame, selected
machine/tool/setup and explicit process settings. Cancellation, logs, output
validation and retention belong to the existing execution/resource authority.
An unavailable computation remains unavailable; source imagery and illustrative
rendering are not simulation evidence.

No proposed record above authorizes computing a toolpath, writing a machine file
or controlling equipment. No machine configuration or user's scientific source
is modified by this design document.
