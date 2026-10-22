# GX-TXT Viewer Provider API v1

SPDX-License-Identifier: GPL-3.0-or-later

Viewer Provider is distinct from Graph Provider: a Graph Provider offers static
plots/axes, while a Viewer Provider exposes an interactive or otherwise
backend-owned scientific view. CORE does not prescribe a graphics toolkit.

## Descriptor

A Standard Module API descriptor may declare:

```ini
[viewers]
api_version=1
ids=example.scene

[viewer.example.scene]
name=Example scene
backend=example_backend
activation_api=EXAMPLE_VIEWER_API_v1
; or backend_script=runtime/example_viewer.tcl for a private backend
supported_primitives=points;surface;triangle_mesh;trajectory;geometry
artifact_formats=csv;stl;vtu
capabilities=multilayer;camera;clipping;opacity;scalar;vector
```

`activation_api` is optional. When present it must name one of the same
module's declared `[public_apis]` IDs. It tells CORE how to lazily activate the
module-owned backend when Open or Rerender is requested. Providers may omit the field and use process-local backend registration.

`backend_script` is an alternative for a plugin-private Tk or other Tcl viewer
that does not expose a public API solely for activation. CORE lazily sources a
relative `.tcl` file inside the declaring module when Open or Rerender needs the
backend. The file must register the declared backend through
`viewerBackendRegister`. `backend_script` and `activation_api` cannot both be
set. CORE rejects absolute paths, parent traversal, missing files and symlinks.
Existing `activation_api` providers keep their behavior.

Viewer IDs are stable within a module. The provider appears in the Viewers catalog while it is installed and its presentation flag is enabled.

## Lazy backend activation

Provider discovery is intentionally headless. Calls such as:

```tcl
::GX::viewerProviderIds module_id
::GX::viewerProviderDefinition module_id viewer_id
::GX::viewerProviderList
```

do not activate the provider's public API and therefore do not load Tk, Qt,
OpenGL, a Python GUI or another desktop dependency merely because the provider
is installed.

When a user or caller requests:

```tcl
::GX::viewerOpen module_id viewer_id ?open_context_dict?
::GX::viewerRerender module_id viewer_id
```

CORE performs this lifecycle:

```text
provider definition
→ existing backend registration, if already active
→ otherwise activate provider activation_api through modulePublicApiActivate,
  or source its declared plugin-private backend_script
→ verify that the declared backend registered successfully
→ resolve the current Viewer scene
→ dispatch open/rerender to the backend
```

Activation is lazy and idempotent. `modulePublicApiActivate` remains the
public API loader; `backend_script` loads only a path-checked Tcl file owned by
the already installed module. Repeated Open/Rerender calls reuse the
process-local backend registration.

Activation failures are explicit. Typical diagnostics distinguish:

- failure while activating the declared public API;
- activation API completing without registering the declared backend;
- a legacy provider with no activation metadata whose backend is unavailable.

A desktop adapter may be loaded by the activation API, but descriptor discovery
itself must remain host-independent.

## Scene and layer API

CORE exposes:

```tcl
::GX::viewerProviderIds module_id
::GX::viewerProviderDefinition module_id viewer_id
::GX::viewerProviderList
::GX::viewerSceneSet module_id viewer_id fields
::GX::viewerSceneGet module_id viewer_id
::GX::viewerLayerSet module_id viewer_id layer_id fields
::GX::viewerLayerGet module_id viewer_id layer_id
::GX::viewerLayerIds module_id viewer_id
::GX::viewerLayerRemove module_id viewer_id layer_id
::GX::viewerAttributeSet module_id viewer_id layer_id attribute_id fields
::GX::viewerAttributeIds module_id viewer_id layer_id
::GX::viewerAttributeRemove module_id viewer_id layer_id attribute_id
::GX::viewerSceneResolve module_id viewer_id ?presentation_context_dict?
```

A scene stores camera position/target/up, projection and clipping planes. A
layer has a stable layer ID, a supported primitive kind, Dataset or artifact
source identity, visibility/opacity and optional scalar presentation. Dataset
bindings use stable Dataset/variable IDs. Artifact paths are Session-relative,
symlink-free and SHA-256 verified before dispatch.

Scene fields preserve the generic Native 3D Engine
presentation state: `background_rgb`, `background_bottom_rgb`,
`background_gradient`, `lighting`, `lighting_ambient`, `lighting_diffuse`,
`lighting_specular`, `lighting_direction`, `lighting_color`,
`lighting_intensity`, optional `lighting_lights` (up to four semicolon-separated
`dx,dy,dz,r,g,b,intensity` records), `clip_box` (`minx;miny;minz;maxx;maxy;maxz`),
`axes_world`, `axes_local_layer`, `axes_reference_marker`, `axes_size_pixels`, and
`working_plane_origin/normal/u_axis/visible`. Camera presets commit their
result to the existing camera fields. The first light fields remain useful to
existing single-light consumers. New layer fields are `base_color`,
`line_width`, `point_size`, `backface_culling`, `scalar_coloring`, and
`representation=surface_edges` alongside existing style, visibility, opacity,
scientific roles and source fields. All of these are descriptors; authoritative
geometry and Dataset payloads stay in their source files.
`sphere_glyphs` selects the existing point presentation: omit it or use an
empty value for legacy kind-derived behavior, `0` for native point markers,
or `1` for geometric spheres on a point layer/representation. Other values
are rejected before replacing the previous layer. Native markers use
`point_size` in screen pixels; geometric spheres are transformed with the
geometry. An explicit `radius_array` still requests radius-driven geometry;
it must not be used for ordinary screen-sized scatter markers.
Scientific scatter with independently normalized axes of different
physical units should use `sphere_glyphs=0` and `representation=points` to
avoid stretching geometric glyphs. This changes presentation only: source
points, scalar arrays, physical axis units and source SHA checks are retained.
The option persists with the layer and survives Session reopening. Existing
layers without it retain their previous behavior; no native rebuild is needed.
`opacity_array` optionally names a point scalar array with values in `[0,1]`;
the engine maps it to per-point opacity independently of layer opacity.
`local_transform` optionally stores 16 finite column-major affine matrix values
separated by semicolons. The native object manipulator writes this field only
when its drag is accepted. A layer with multiple STEP occurrences requires a
separate per-occurrence model before a persisted object transform can be
applied safely; the adapter rejects that case.

`marker_definitions` is a bounded Tcl list of dictionaries with stable `id`,
`layer_id`, `occurrence_index`, object `local_point`, `kind`, `size_pixels`,
`color`, and `visible`. `measurement_definitions` is a bounded list of
dictionary records with stable marker references and distance/delta/angle
kind plus visual style. `curve_definitions` similarly records source layer and
occurrence, defining plane, section/profile/projection kind, style and join
tolerance. The engine adapter recreates queryable anchors and derived curves
from these compact definitions on rerender; no transient VTK cell IDs or
generated geometry are stored in Session metadata. Source SHA checks run
before reconstruction, and a missing source occurrence is an error.

Viewer scene/layer state is presentation/configuration state. It must not be
misused to serialize unrelated authoritative scientific documents. Interactive
providers whose scientific user state is richer than a Viewer scene should use
[Interactive Document API v1](INTERACTIVE_DOCUMENT_API_v1.md).

## Backend dispatch

A renderer integrates with:

```tcl
::GX::viewerBackendRegister backend_id command_prefix
::GX::viewerBackendEnsure module_id viewer_id
::GX::viewerOpen module_id viewer_id ?open_context_dict?
::GX::viewerRerender module_id viewer_id
```

`viewerBackendRegister` remains process-local. `viewerBackendEnsure` is the
lifecycle helper that performs optional lazy activation and returns the
registered command prefix. `viewerOpen` and `viewerRerender` both use it.

The callback receives action (`open` or `rerender`) and a resolved scene
dictionary containing the provider declaration, view state and layers. A
backend may open/focus its own window; Viewer Provider does not promise an
embedded parent Tk widget or generic canvas.

`viewerOpen` may receive a one-call `open_context_dict`, exposed to the backend
as `open_context` in that dispatch dictionary. Dataset Preview uses this to
pass the selected source path, media type, contract and format to a viewer.
The context is invocation state; the provider must explicitly register any
source it wants to preserve in the Session.

For a dedicated scientific presentation, `presentation_layer_ids` in that
context explicitly selects registered layer IDs. `viewerSceneResolve` accepts
the same optional context. Selection occurs before resolving source artifacts
or Dataset bindings: unrelated stored sources are preserved and are not added
to this presentation. Duplicate or unknown layer IDs reject, and all selected
sources retain the normal identity, revision and digest checks. Omitting the
key retains the existing complete multilayer scene; an explicit empty list
selects no layers.

After a successful scoped `viewerOpen`, `viewerRerender` retains that active
subset. A failed open does not replace it. A subsequent unscoped `viewerOpen`
restores the full multilayer presentation. This process-local dispatch scope
is cleared by Session load/defaults and is not saved as scientific state.
The Molecule Viewer uses `{presentation_layer_ids molecule_main}` so retained
Crystal Viewer layers do not obscure a molecular structure. Their original
sources, layer descriptors and resources remain stored and available.

`rerender` means "refresh from authoritative/persistent state as appropriate to
the provider". It must not silently destroy authoritative user work.

## Scientific scenes

The existing v1 API now accepts `scene_mode=automatic|scientific` in
`viewerSceneSet`. Scientific mode opens a renderer without a base file. The
normal path is Acquisition → canonical Dataset → Viewer layer → shared native
renderer. The viewer can select compatible Session Datasets through Session
Inspection; opening the viewer never automatically opens a file chooser.

Generic layer kinds are `points`, `trajectory`, `surface`, `triangle_mesh`,
`geometry`, and `isosurface`. A layer may bind a canonical Dataset by
`source_mode=dataset`, `dataset_id` and `format`, or a Session artifact by
`source_mode=artifact`, `resource_path`, `sha256`, `format`, and
`format_version`. Use `viewerArtifactRegister` for derived VTP artifacts.
`source_dataset_id` plus `source_dataset_sha256` binds a derived artifact to
its scientific source; resolution fails explicitly if the source changes.

Presentation fields include `layer_order`, `visible`, `opacity`,
`representation=surface|wireframe|points`, `scalar_array`, `vector_array`,
`colormap`, `scalar_range`, `radius_array`, `tube_radius`, and `isovalues`
(semicolon-separated). A regular scalar grid may be a canonical VTI Dataset;
an isosurface layer names its scalar array and one to 32 finite isovalues.
VTP points with a radius array become atom-like sphere glyphs; indexed VTP
lines with `tube_radius` become bond or trajectory tubes. A three-component
point `vector_array` becomes sampled arrow glyphs in the same scene. Species, bond order,
units and other scientific metadata remain in the Dataset and VTK arrays.
These are generic primitives; molecular and crystallographic modules do not
need renderer internals or special windows.

`viewerSceneResolve` verifies Session payloads and digests before dispatch.
`viewerLayerRemove`, `viewerSceneSet`, `viewerOpen`, and `viewerRerender`
provide remove, camera/view/clipping state, open, and refresh. Session save
persists scene presentation; derived native geometry and display caches can be
rebuilt. The native backend currently reads STL/OBJ/STEP geometry via its
worker and VTU/VTP/VTI scientific layers via VTK. It renders isosurfaces,
point glyphs, lines/tubes, meshes and scalar-colored surfaces. Export is a
backend screenshot; the static publication graph path remains Graph Provider.

`viewerSceneSet` fills unspecified fields from defaults. To change only one
camera or clipping field, merge it into `viewerSceneGet` before setting.
Native 3D's Dataset selector includes VTP and VTI. Selecting VTI requires an
explicit scalar array name and one or more isovalues; the renderer does not
guess a scientifically meaningful level from arbitrary payload values.

The API is the module-facing boundary. Native worker commands, Tk widgets,
cache files and VTK/OCCT objects are private implementation details.

### Independent Plot Dataset interactive representations

Plot Dataset API v3 enumerates persistent graph/Variant sources and asks its
own scientific exporter to build a Viewer scene. The source graph/Variant and
Viewer representation have separate persistent identities. Native 3D's
Source type selector offers Imported 3D Dataset and Plot Dataset 3D graph.
The Viewer does not infer scientific meaning from arbitrary Dataset columns
or use a rendered PNG/PDF filename as graph identity.

Plot Dataset representation documents hold source provenance and the last
successful source fingerprint. Source edits leave the existing derived scene
unchanged and report `OUT OF SYNC`; only an explicit Sync rebuilds it. A
deleted exact graph/Variant reports `SOURCE MISSING` without deleting the
Viewer representation. The status is recomputed on Session reopen. Derived
Plot Dataset VTP artifacts live under independent Session Viewer resources.

`viewerLayerSet` now accepts `source_update_policy=strict|snapshot`.
`strict` is the existing default: a source Dataset digest must still match
when the scene is resolved. `snapshot` is valid only for a hash-checked
Session artifact layer whose source Dataset identity is retained as
provenance. It allows an existing derived view to remain inspectable when
its scientific source changes or disappears; Plot Dataset's source
fingerprint/status and explicit Sync remain the authority for updating it.

`viewerSceneSet` also persists `background_rgb` (three 0..1 components) and
`lighting` (0/1) alongside camera, projection and clipping. Native 3D
replays these presentation fields after reopening or explicit Sync.

## Persistence and runtime

The `viewer.engine_3d` scene accepts lightweight
`timeline_definitions`, `active_timeline_id`, and `field_definitions` in the
same Viewer Provider scene record. Each timeline has an ID, unit, ordered
sample times, playback rate/mode/range and current time, with named tracks
whose frame entries refer to ordinary Viewer layers. A field definition
retains a source layer or track ID, seed list/line/plane, integration direction
and budgets, and derived presentation parameters. Source layers continue to
carry Session artifact paths, Dataset/Variable IDs, source SHA and provenance
through their ordinary Viewer Provider descriptors. Scientific arrays stay in
their source artifacts, never in the manifest. The native worker lazily loads
track frames and recreates bound lines, pathlines, slices and isosurfaces on seek.
It restores saved stopped, paused or playing state; playing resumes the GUI
timer after the initial render. Saved frame/time conflicts are rejected with an
explicit Provider error. A fresh process rejects missing or changed source
artifacts before presenting them.
The Tk controls call native animation, field and viewport manipulation APIs;
no interpolation or drag geometry is computed in Tcl.

Manifest Format 2 continues to store indexed `viewer_scene`, `viewer_layer` and
`viewer_attribute` sections. Existing Sessions and providers remain valid.
Standard module runtime configuration contains `viewer_runtime` sections for
enabled providers.

This presentation persistence is separate from authoritative interactive
scientific state. CORE provides Interactive Document API v1 for such
state. Module Reset/runtime-cache cleanup must not delete Interactive Documents.

No automatic conversion from Graph Provider plots occurs. A module can expose
both static plots and Viewer Providers.

## Compatibility

Activation metadata is optional:

- `activation_api` is optional;
- existing `viewerScene`, `viewerLayer`, `viewerAttribute` and Manifest Format 2
  behavior is preserved;
- providers that register backends by their established lifecycle continue to
  work without `activation_api`;
- headless discovery does not activate desktop code.

## Physical camera fields

Scene descriptors add `orthographic_height` (positive physical world height;0 preserves
legacy camera-distance behavior), `near_clip`, `far_clip`, and `navigation_cube_visible`.
Clip distances default to0/0 (legacy automatic policy); explicit distances must be finite, positive, with far>near. Layer descriptors add
`color_array` for existing native point/cell direct RGB/RGBA mappings. Scene persistence
retains these fields. Reference rendering uses an explicit plane-aligned camera and
calibration; ordinary Viewer camera semantics remain. The complete workflow uses the
modern `viewer.engine_3d`; `viewer.native_3d` remains available as a deprecated provider.

## Orientation presentation

Viewer Scene's boolean `orientation_indicator_visible` defaults to 0 and follows
the existing scene validation/persistence path. Native3D renders it in a separate
transparent viewport layer, independent of world-axis settings. Numerical XYZ
sets it to 1 with `axes_world=0`; modern scientific Plots retains its calibrated
axes/colorbar policy. Existing scene APIs carry the field; no parallel scene
registry or new scientific scripting operation is needed.

## Catalog presentation and enablement

Each `[viewer.ID]` descriptor can supply `short_title`, `semantic_group`, `group_title`, and `icon=icons/NAME.png`. Bundled providers have distinct scientific SVG masters and sharp 192-pixel PNG artwork; the normal catalog displays at least 64-pixel images, with native higher-resolution artwork for scaling. Icons must be safe module-relative PNGs; traversal, symlinks, missing files and files over 2 MiB are refused. External descriptors without artwork use the framework fallback and existing name/category defaults.

`viewerProviderCatalog` reads installed descriptors without activating desktop backends. `viewerProviderDefinition module viewer ?include_disabled?` includes presentation metadata and `enabled`. `viewerProviderEnabled` and `viewerProviderSetEnabled module viewer boolean` use the existing account-local Configuration authority. Config → Modules has separate Services and Viewers tabs. Disabling a Viewer removes its launcher and refuses subsequent Open/Rerender; active Workspaces and essential scientific services remain available. Enabling checks installed dependencies. This is a presentation flag, separate from Analysis Run selection and module service state. In particular, Python/Octave script editors remain available when their Analysis Run checkbox is off; opening an editor does not select it for scientific execution. It survives restart through Configuration's atomic writer.

The catalog groups short titled icon buttons by scientific purpose, offers search, keyboard focus/Enter, readable tooltips, scrolling and responsive columns. Provider IDs remain stable technical identities and are available in tooltips and management details. These GUI operations are host-only; provider discovery and scientific API activation retain their existing public contracts.

### Descriptor-driven legacy presentation

`viewerProviderDefinition` additionally exposes boolean `deprecated` and a
`replacement` module/provider reference, reading provider fields first and module
metadata as fallback. The catalog labels a deprecated presentation as legacy and
its standard tooltip identifies the successor. Neither field disables or migrates
the original scientific provider, Workspace or public API.

Optional provider `catalog_replacement=MODULE/VIEWER` suppresses only that old
launcher while the named installed replacement presentation is enabled.
`viewerProviderCatalog ?includeReplaced?` defaults to the normal single-launcher
catalog; pass true for the full descriptor inventory. The original provider still
opens normally through its registered identity. Absent/disabled replacements leave
the legacy launcher available. References must name another registered Viewer;
this is presentation metadata, not a second dispatcher or scientific model owner.

The existing EM model Workspace owner prefers the installed compiled presentation
through `viewerOpen` and passes only `em_document_id`; otherwise it uses the normal
legacy Viewer dispatcher. Model identity/schema and publication remain with the
original mathematical service. Installed binary validation and strict SDK/runtime
compatibility still occur through the common compiled Viewer lifecycle.
