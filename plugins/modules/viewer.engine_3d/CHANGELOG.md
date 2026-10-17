## 0.1.5 — dev097

- Canonical CORE native loader and removal of duplicated packaged native implementation.
- Reconciled module, package and current producer identities for this release.

## 0.1.4

Compatible adapter update for the dev071 CORE-owned rendering and scientific decoder services. Requires framework dev071 or newer.

# viewer.engine_3d changelog

## 0.1.3 — GX-TXT0.9.8.10-dev-052

Shared Workbench host, safe coalesced gesture cancellation, complete canonical geometry Dataset intake and read-only Native handle picking.

# Changelog

## 0.1.2 (GX-TXT 0.9.8.10-dev-038)

- Widen the temporary control band and show the CORE Navigation Cube. Forward cube picks and clicks to public CORE/API camera orientation.

## 0.1.1 (GX-TXT 0.9.8.10-dev-035)

- Forward the persisted global Native 3D shadow rendering preference to the CORE graphics policy.


## 0.1.0 (GX-TXT 0.9.8.10-dev-032)

- Add Viewer Provider adapter, native Tcl bridge, PNG viewport and Session state controls.
- Add public-API transform gizmo forwarding, axes and marker/measurement/curve persistence,
  explicit-resolution PNG export, progressive import and isolated worker budgets.
- Verify the Linux RSS watcher with a 256 MiB child: 128 MiB budget terminated it
  with a measured 264.6 MiB diagnostic; 4096 MiB budget allowed completion.
- Forward orbit, pan and wheel input to CORE navigation; queue and coalesce
  events that arrive while the isolated renderer worker is busy.
- Add VTI volume transfer controls and preserve volume presentation through
  Session save and fresh-process reopen.
