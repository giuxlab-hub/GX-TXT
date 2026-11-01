# Native3D component gap and additive CORE extension

The verified predecessor is official dev106 archive SHA-256
`08a629e05d801279cddcf874a68c3c8b65b877a83cfd697d2847ec9e3fa45777`,
overlaid byte-for-byte before dev107 changes in baseline commit
`d9d3aa1981f32ca52e621310827477c50d12953a`.

In that immutable predecessor, `core/tcl/native3d_gui_host_v1.tcl:3` owns the
`::GX::Engine3D` namespace; line 4 declares its one `.gx3de_viewer` window.
Lines 52–61 declare one worker, worker generation, transport, busy flag and RSS
timer. Its API discovery at line 170 explicitly returns `shared_renderer=1`
and `shared_worker=1`. `Engine3D::setHostIdentity` at line 175 closes the existing
worker/window when a different registered module/provider becomes owner. This
is a genuine shared editable host, not an independent portable child viewport.
The predecessor's `viewerGuiComponentCapabilities` therefore correctly marks
the Builder `native3d` slot as `CORE_GAP`.

Dev107 preserves that legitimate v1 client. The additive public
`NATIVE_3D_GUI_HOST_API_v2 @ 2` in `core/tcl/native3d_gui_host_v2.tcl` owns opaque
per-component handles: child frame/canvas, real renderer worker, scene, camera,
source generation, queue, subscriptions, timers and disposal. Four live/retiring
owners are the application limit. Actual reaping completes before a replaced
worker starts; parent destruction affects only its owned instance.

The rendering authority remains the existing native engine and read-only
renderer worker. `libgx3de.so` remains byte-identical to accepted dev106
(`953fafba14b45c3a77872a9bea7ffe14148856a74bd85093ac4edac8f1834520`).
Only the existing Tcl bridge gains a bounded RAM mesh input path calling that
engine's `gx3de_object_create_mesh`. The GUI transfers each newly rendered native
frame into its embedded Tk child; it does not display a static screenshot or
open a detached Engine3D application. Actual native camera and pick receipts
accompany pointer/key navigation. There is no alternate Builder graphics stack.

The versioned contract includes create/configure/update, public source
bind/unbind, camera/navigation/presets/pick, events, inspect and release. Normal
Tk geometry/container lifetimes provide resize and notebook unmapping. Builder
properties and generated connectors require the actual API/version. Shared CORE
discovery exposes this same capability to the restricted C++ SDK broker.

Scientific binding resolves the registered module/provider via public Viewer,
Dataset and native scene preparation owners. Exact Dataset IDs, units, source
SHA and Session generation remain scientific authority. RAM cube/axes fixtures
have explicit display-only provenance and cannot publish a Dataset. The v1 scene
preparation implementation is promoted to a public CORE operation with its
compatibility wrapper retained.

Evidence is separated by scope: two-instance navigation and actual picking;
typed Builder camera/projection Save/Open; notebook/resize/rebind and worker
cleanup; ordinary generation/Plugin Manager install; original v1 scientific
client beside v2; public synthetic XYZ scientific binding, stale source/Session,
worker error/rebind; restricted compiled C++ numeric/native integration. See the
165-case acceptance ledger and GUI visual-review log for exact receipts and
remaining installed-release gates. A declaration or RAM-only screenshot does
not establish scientific or installed acceptance.

The orientation cube is rendered as an orientation indicator. Direct cube-face
click navigation and scientific mesh editing are not exposed capabilities.
