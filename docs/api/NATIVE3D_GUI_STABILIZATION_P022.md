# Native3D GUI transport and saved Sketch presentation — P022

SPDX-License-Identifier: GPL-3.0-or-later

These are compatible additions to the existing Native3D GUI Host / Native2D
contracts. Native3D's C ABI, renderer, camera mathematics, scene ownership,
scientific exports and optimized engine library are unchanged.

## Renderer startup

Linux renderer children preload the system `libpthread.so.0` before dynamically
loading VTK/OpenGL. This resolves the reproduced NVIDIA390/TBB null
`pthread_create` trampoline failure on the supported Debian desktop. Existing
preload entries are preserved. Parent environment, scientific Jobs and their
stdout/stderr routes are unchanged. Software still explicitly selects Mesa.
This does not guarantee that an unsupported GPU/display can provide OpenGL3.2.

Explicit Hardware remains explicit. Initial read-only Auto failure retains the
existing single Software retry, with its original diagnostic. A failed/stale
component requires explicit rebind/reopen; pointer/resize events do not restart
it repeatedly. `native3DViewportInspect` additionally returns `worker_policy`,
`frame_transport`, `render_receipt` and the owned `worker_log` path. The initial
render receipt identifies actual execution, device and driver; requested policy
alone is not proof of hardware rendering.

## Lossless intermediate frames

The existing isolated renderer protocol adds:

```tcl
frame_transport png
frame_transport fast_png
frame_transport fast_png /owned/current-frame-copy.png
```

The last form writes an already-rendered frame, without rendering or changing
scientific state. `png` is the standalone transport default. Linux GUI owners
select `fast_png` after greeting. It reads the existing public
`gx3de_target_read_rgba` buffer and uses libpng's lossless compression1 / no-filter
encoding for the replaceable intermediate frame. RGBA8 orientation, alpha and
untagged color interpretation are preserved. No resampling occurs. Explicit
scientific export/supersampling/capture continues using the existing encoder.
The Tcl transport CMake target now requires PNG; the engine target is unchanged.

Render and navigation receipts include bounded `timings_ms` fields `prepare`,
`native_render` and `png_write`. These are wall-clock API spans, not GPU timer
queries: native rendering includes authoritative framebuffer capture, and PNG
time includes encoding/file output. They exclude parent event-loop scheduling,
IPC handling, Tk PhotoImage decoding and Canvas presentation. No trace stream,
polling or unbounded history is created.

## Ordered camera batching

```tcl
navigate_batch {{orbit 14 7} {pan 8 -5} {roll 4 0} {zoom 1 0}} /owned/frame.png
```

The compatible renderer command validates1..4096 finite `{mode dx dy}` rows
before mutation. It invokes the same authoritative native camera operations in
order and renders once. It does not add noncommutative rotations together.
Invalid native proposals restore the prior camera/orthographic height. The
receipt includes `navigation_operations`. Individual `navigate` remains valid.
Shared Preview and component owners batch adjacent pending relative inputs;
absolute presentation requests may supersede their own obsolete pending kind.
Queue saturation is explicitly rejected, never silently reported as applied.

## Native2D coordinate batches

```tcl
::GX::Native2D::core world_points $scene $deviceXYRows
::GX::Native2D::core device_points $scene $worldXYRows
```

`NATIVE2D_API_v1` advertises `coordinate_batch`. Each operation accepts at most
65536 finite two-coordinate rows and returns rows in the same order, including
an empty batch. It calls the existing C coordinate conversions for every point;
there is no alternate geometry/unit/coordinate algorithm. A rejected batch has
no scientific side effects. The shared projected CAD presenter uses this path
and retains segment-hit presentation within its existing object/frame cache.
Native mutation and camera-generation invalidation remain mandatory; current
epoch-checked scientific references are refreshed each presentation pass.

## Explicit saved Sketch display

```tcl
set display [::GX::nativeCadSketchDocumentPresentation $documentId $worldUnit]
::GX::native3DGuiHostDocumentPresentationSet $display
::GX::native3DGuiHostDocumentPresentationInspect
::GX::native3DGuiHostDocumentPresentationRemove $documentId
```

The public Native2D Sketch operation reads the exact saved Document and produces
a bounded display descriptor through Native2D sampling and Native3D's existing
plane-frame authority. It creates no editor/History context, applies no solver
changes, and does not alter source geometry, constraints or units. Native frame
transforms are batched. Unit conversion uses the Unit Registry. The descriptor
contains Document ID/generation/revision, Session token, working unit and layers.
Sampling follows the existing bounded visual-snapshot policy (129 points per
constituent, at most4096 constituents); it is not scientific export or measurement
geometry. Exact definitions remain the authority.

The existing Native3D GUI Host retains this derived renderer resource for its
current owner. Generation/revision/Session checks reject expired snapshots;
stale entries are removed during full-scene preparation. No Document, Dataset,
History or canonical scene registry is introduced. The consumer explicitly
registers/removes resources and requests a normal renderer refresh. Host close
releases all of them. Camera navigation reuses retained native scene geometry.

Managed Sketch `close` keeps its previous no-argument contract. Optional
`close $worldUnit` saves, prepares this display before destruction, and returns
`display_snapshot` with its normal closed receipt. Preparation failure leaves
the editor alive. Pending edits still require the existing explicit decision.

Workbench integrates this at editor close and associated-Document restoration;
it removes the matching static layer while that Sketch is actively edited.
There is no continuously synchronized second Canvas/scene. Closed drawings use
normal Native3D depth/occlusion. Active editing feedback remains the existing
transparent, always-on-top overlay. Borrowed-viewport editing requires matching
working coordinate units; mismatched scales are rejected without changing
science. Closed displays may be converted independently through CORE.

## Temporarily non-editable views

Edge-on, horizon-crossing or behind-camera plane projections suspend CAD pointer
interpretation. Such input must not reach scientific proposal rejection, which
would cancel staged construction. Native camera navigation and explicit
Finish/Cancel remain available. A later valid native camera receipt restores
editing; no Sketch/History/Document is destroyed because of camera orientation.
