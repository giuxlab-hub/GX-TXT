# Retained planar edit and originating3D Workspace return

This is an additive contract of `NATIVE_3D_GEOMETRY_API_v1`, using existing
PlanarDocument, Native2D Curve Workbench, Native3D Profile and Document Resource
owners. It introduces no new API identity, geometry kernel, Workspace store or
cross-document transaction engine.

The installed3D Workbench's **Edit section in Curve Workbench…** and **Edit
projection in Curve Workbench…** use its selected real body and current working
plane. The source is exported from complete native world geometry; an exact
B-Rep is tessellated only with the recorded explicit bounded policy for the
piecewise-linear section/projection. The source body remains unchanged. The
extracted contours retain their true physical unit, right-handed plane, source
SHA and approximation/lost-depth receipt. A solid without a usable editable
boundary explains that limitation instead of inventing a contour.

`native3DPlanarOriginReceipt document_id object_id` captures the actual originating
registered owner, document generation/revision/SHA, source body/geometry SHA,
working unit and scientific Session origin. `native3DPlanarOriginValidate receipt`
rechecks these authorities. The current concrete destination adapter belongs to
`viewer.3d_workbench/workbench_3d`; a different Workspace schema requires its own
registered owner contract. CORE never writes an unknown provider's payload.
`native3DPlanarCreate path unit plane tolerance {origin_workspace RECEIPT}` binds
that receipt and normalized frame to the existing PlanarDocument. The existing
EditBegin/EditAccept contracts still guard the PlanarDocument and Session lifetime.

Edit actual retained contours in Curve Workbench. **Accept →3D** first commits an
independent accepted Planar result. Paths retain exact piecewise-linear vertices;
other supported retained families retain their exact definitions plus explicitly
labelled257-sample geometry. This is not an exact inverse reconstruction of lost
3D depth. The accepted result then enters the originating owner's ordinary profile
transaction, preserving its document ID, original body, physical frame, sources,
Undo/Redo and managed resources. New profile geometry is owned by that destination;
no transient pointer, temporary path or widget ID becomes scientific storage.

`native3DPlanarOriginCommit planar_document_id` performs the second step through
the existing3D Workbench owner. It stages/copies resources, validates units/frame
and source freshness, creates a native profile, and uses existing commit/rollback
and History. Success returns destination document/profile IDs and explicitly
states `transaction_scope=destination_owner_only`. An interrupted presentation
acknowledgement can be retried idempotently for the same accepted result.

These are **two independent owner commits**. If destination commit fails, the
accepted Planar result remains retained and the originating3D science remains
unchanged. Curve Workbench retains a durable pending-return context and offers
**Commit staged result →3D**; it does not falsely claim that both owners rolled
back. A changed/deleted/replaced origin requires explicit new extraction. Cancel
abandons the live edit without writing to the origin; an already accepted staged
Planar result remains independently available. Source, units, frame and accepted
provenance survive normal Session/Workspace persistence.

This workflow adds a planar profile. Extrusion, Boolean use or replacement of an
original body remains an explicit separate operation. Texture appearance and
pixel alpha do not imply a geometric profile or manufactured relief.
