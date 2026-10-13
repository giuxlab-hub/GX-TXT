# Native 3D Engine Viewer

The **Native 3D Engine Viewer** is a Viewer Provider backed by `libgx3de`.
Its renderer quality, execution mode and resource limits come from
**Configuration → Viewers → Native 3D graphics / performance**. Save settings
before using **Check Native 3D runtime** to see the effective backend, device
and execution type. Presets set display quality, interaction LOD, MSAA,
transparency and triangle budget; changing a mapped value gives Custom. GPU
use is an estimate unless the backend reports measured use. Export
supersampling affects explicit PNG export only. These preferences are user
defaults, not Session state.
The Shadow rendering preference is global and persisted there. Low turns
shadows off, Medium allows opaque casters, and High/Ultra allow opacity-attenuated
translucent casters. Custom lets you select Off, Opaque objects only, or Opaque
and translucent objects. The preference is forwarded to the CORE graphics
policy; scene, object and light shadow flags remain effective within that limit.
Open a Session, select it in the Viewers tab, add a Session artifact or Dataset
point/trajectory layer, and click **Rerender**. The scene and layer descriptors
are stored by Viewer Provider API v1 in the Session manifest. Geometry remains
in its source artifact or Dataset payload. Sources are SHA-256 checked on each
open and rerender. A changed or missing source produces an explicit error.

The temporary viewer shows a native PNG render in Tk beside a 460-pixel
scrollable control band. The upper-right Navigation Cube is view-owned CORE
geometry. Clicking one of its face, edge or corner regions calls CORE cube
picking and camera selection; the resulting camera is persisted in the viewer
scene. Outside the cube, a click performs native geometry picking; left-drag
orbits, middle-drag pans, and the wheel zooms the persisted camera.
**Mark selected point** creates an object-local scene marker; marker
IDs can be used for distance, delta and angle measurements. A selected source
layer can produce a section, profile or projection from the working-plane
entries. The scrollable controls also edit camera presets, projection,
clipping planes/box, working plane, background, lighting, per-layer style,
visibility/opacity, scientific roles/range/colormap and PNG export.
PNG width and height select the export resolution without changing the
interactive viewport or its camera. The working plane is edited by origin,
normal and U-axis fields; this generic GUI has no draggable plane handle.
Camera input is forwarded to the Native 3D CORE. Motion is coalesced while a
worker render is in progress; the final requested camera state is rendered.
VTI layers can be shown as isosurfaces or as a volume with explicit ordered
scalar-to-color/opacity transfer points and ray sample distance. These
presentation settings are saved with the Viewer Provider layer and restored
when the Session is reopened. The separate public field and animation APIs
are documented in `docs/api/NATIVE_3D_FIELD_ANIMATION_API_v1.md`; this generic
viewer does not yet provide a timeline editor or timeline Session serializer.
Select a single-object layer and click **Manipulate selected object** to display
the native translation/rotation handles. Left-drag a colored handle to preview
and commit its object transform. The committed transform is stored in the
Session layer descriptor; a cancelled drag restores the prior pose. A STEP
layer containing multiple occurrences is not offered a single layer transform,
because one matrix cannot preserve distinct occurrence placements.

STL/OBJ and STEP layers can first display a native preview/coarse tessellation,
then the configured normal representation. The worker is a separate process with an
address-space limit and, on Linux, a sampled resident-memory limit. The
resident check runs every 250 ms during requests; it reports the measured
usage and kills the child if the configured limit is crossed. Cancellation
is available during import and render. Auto execution retries a qualifying
renderer failure once under Mesa llvmpipe without changing the main GX-TXT
environment. Hardware reports failure instead of falling back; Software
deliberately starts the Mesa path. The
source model remains authoritative. A rendering window is not the source of
truth for the scene; the Viewer Provider descriptor is.
An isolated worker-budget check used a 256 MiB child: the 128 MiB RSS limit
terminated it with a 264.6 MiB measured-use diagnostic, while a 4096 MiB
limit let the child finish. The 250 ms sampling interval permits brief
transient overshoot; the address-space limit remains a separate hard process
limit on supported Unix hosts.

`viewer.native_3d` remains installed and untouched for legacy workflows.
