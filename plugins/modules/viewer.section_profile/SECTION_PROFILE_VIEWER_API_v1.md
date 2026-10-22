# SECTION_PROFILE_VIEWER_API_v1

The `viewer.section_profile` module registers the `section_profile_tk` backend through `VIEWER_PROVIDER_API_v1`. Open it with `::GX::viewerOpen viewer.section_profile section_profile [dict create dataset_id SOURCE_ID]`. The backend is activated lazily by the Viewer Provider API.

The viewer resolves source payloads through Session Inspection, reads canonical tables through Dataset Access, invokes `NUMERIC_API_v1` geometry actions for frames and extraction, and publishes through Dataset Publication API v2. It has no private mesh intersection or coordinate-frame implementation. The output is a standard Dataset with plane and source provenance in Dataset Metadata API v1.

When opened, the viewer subscribes to public Native 3D interaction events. A `plane` event updates its working O/N/U/V frame. A `pick` event adds a world point and any available surface normal and native point/cell identifiers to the GUI pick list. The viewer unsubscribes when its window closes. `::GX::Native3D::setWorkingPlane` displays the frame in the native host and keeps numeric and mouse manipulation aligned.

## Viewer Provider callback

`::GX::SectionProfile::viewerDispatch {action scene}` is the trusted Tcl Viewer Provider callback. `action` must be `open` or `rerender`; unsupported actions raise an error. `scene` is a resolved Viewer scene dictionary. A compatible `scene.open_context.dataset_id` selects that canonical source; otherwise the sole compatible Dataset is selected only if no source is already selected. The result is the existing `.section_profile` Tk window path. Opening this Viewer is not a profile-extraction receipt: Native3D events, public Unit/Numeric services and canonical Dataset Publication retain geometry, units and scientific-result ownership. This host callback adds no Script/SDK permission.
