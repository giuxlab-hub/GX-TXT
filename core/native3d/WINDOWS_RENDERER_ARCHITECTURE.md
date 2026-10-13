# Windows renderer boundary for Native 3D Engine API v1

The public C ABI uses opaque engine, scene, view, target, viewport, object and
anchor handles. It carries no VTK, OpenGL, Direct3D, Win32 widget or C++ ABI
types. Session state and scientific provenance are maintained above the
renderer. A backend choice therefore cannot change their representation.

## Current implementation and exact limit

The Linux renderer is VTK OpenGL2. The backend-neutral target API selects
OpenGL or D3D11 and queries adapter, execution and failure diagnostics. On
Windows, the D3D11 path creates a hardware device/context, offscreen color and
depth targets, a Win32 swap chain for native targets, vertex/pixel shaders and
RGBA staging readback. It submits mesh, tessellated B-Rep and scientific
surface/point geometry directly to D3D11 and recreates size-dependent targets
on resize. Selection fails explicitly if hardware D3D11 is unavailable.

The native library still requires VTK OpenGL modules at build time, though the
D3D11 render path does not use OpenGL. The D3D11 path does not yet provide
volume transfer rendering, overlay/gizmo/picking parity, clipping, scalar
colormaps or device-loss recovery. This Linux host has no Windows SDK or
Windows compiler/runtime, so the Windows branch cannot be compiled or run
here. Windows build and hardware acceptance remain required.
The `viewer.engine_3d` Tcl bridge is currently built by a Unix shell script;
Windows packaging of that bridge also needs a native Windows build procedure.

## Further Windows parity work

Further backend work should consume a renderer-independent display
snapshot built from the existing scene/view state. That snapshot needs object
geometry/prototype references, transforms, material/opacity, scientific
arrays, lights, camera/projection, clipping, overlays and stable object/anchor
identity. It should not embed VTK actors or cell IDs. The same snapshot can
feed the current OpenGL renderer and a D3D11 renderer without changing the
public scientific API, Session schema or rigid manipulation logic.

The remaining D3D11 work is a resource cache keyed by immutable geometry
fingerprints, device-loss recreation, scientific volume/array presentation,
clipping, picking IDs, gizmos, markers and overlays. Compare these with Linux
semantics on Windows hardware before declaring Windows presentation parity.
D3D12 can be added behind the same snapshot boundary later.
