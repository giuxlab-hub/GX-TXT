# SECTION_PROFILE_VIEWER_API_v1

The `viewer.section_profile` module registers the `section_profile_tk` backend through `VIEWER_PROVIDER_API_v1`. Open it with `::GX::viewerOpen viewer.section_profile section_profile [dict create dataset_id SOURCE_ID]`. The backend is activated lazily by the Viewer Provider API.

The viewer resolves source payloads through Session Inspection, reads canonical tables through Dataset Access, invokes `NUMERIC_API_v1` geometry actions for frames and extraction, and publishes through Dataset Publication API v2. It has no private mesh intersection or coordinate-frame implementation. The output is a standard Dataset with plane and source provenance in Dataset Metadata API v1.

When opened, the viewer subscribes to public Native 3D interaction events. A `plane` event updates its working O/N/U/V frame. A `pick` event adds a world point and any available surface normal and native point/cell identifiers to the GUI pick list. The viewer unsubscribes when its window closes. `::GX::Native3D::setWorkingPlane` displays the frame in the native host and keeps numeric and mouse manipulation aligned.
