# dev-053 implementation inventory

The published dev-052 archive (`296f4c1e486b069352a8236891ca45398969887402b6d8cc87451b548ff8cfeb`) is the baseline. The single `_work_gxtxt_dev053` tree was copied from its verified expanded release.

| UX need | Authority and implementation |
| --- | --- |
| Retained geometry, evaluation, exact parameters, sampling | Existing `gx2d_sketch_*` C API |
| Canvas construction | Additive Native2D construction from defining world points |
| Defining handles and selection references | Additive Native2D handle descriptors and topology/parameter-epoch references; existing logical Workbench IDs persist native references |
| Direct control edits | Additive Native2D inverse-affine handle edits, validated against existing constraints |
| Move/rotate/scale | Existing Native2D affine and gizmo/drag APIs |
| Placement snap | Existing grid authority, extended Native2D query for defining handles, centers and midpoints |
| Constraint availability/reference construction | Additive Native2D selection query returning existing v2 constraint descriptors |
| Constraint/dimension adoption | Existing constraint model, extended atomic direct enforcement for supported primitives; no general nonlinear solver |
| Mixed types | Existing record identity, retained definition and source binding; presentation distinguishes source, primitive and point geometry |
| Primitive → Dataset | Existing canonical Publication plus explicit Native2D sampling and existing structured metadata |
| Dataset → exact primitive | Validate canonical publication provenance, source/schema/units and materialized values before existing sketch creation |
| Dataset → fitted primitive | Existing Numerical Curve Fit authority; residual review then explicit acceptance |
| Native materialization | Existing `sketch_materialize`; Dataset conversion remains distinct |
| Viewport clipping | Native2D segment clipping, shared Tk presentation clipping, used by Curve Fit |
| Undo, persistence, recovery, units | Existing Workbench semantic snapshots, Interactive Documents/Session and Unit Registry |

Construction, handles, constraint compatibility/edits and viewport clipping are small bounded computations and remain serial. Sampling/fitting uses existing resource limits and Numerical execution policy. No new parallel worker pool is introduced.


## Operation cost and parallel execution assessment

Construction/preview/from-fit mapping and inverse-affine controls are bounded to at most65536 supplied controls (usual primitives1..4). Compatibility/reference/location queries and direct constraint transactions use current scene definitions and a finite set of existing rules. They remain serial because the scene is owned by one GUI/execution lifetime and candidate/commit ordering is authoritative; process transport or concurrent scene mutation would cost more and compromise that transaction boundary.

Placement snap and device pick may scan complete ordinary Native point objects, including large scientific curves. They reuse existing native pixel/nearest queries in a serial read-only scene scan. A new process pool would require copying scientific scene data per gesture and coordinating mutable viewport/lifetime state; that is not safe/useful parallelism. No full-data Tcl reconstruction or scientific commit occurs on pointer motion. Clipping walks finite render paths/markers (display LOD), and runs serially through shared Native segment math.

Explicit sampling/provenance verification is bounded to65536 values; it remains ordered and serial for reproducible canonical receipts/stream validation. The existing large scientific publication/resource paths retain their own staging/progress/cancellation policy. Fitting performs substantial Numerical work through the existing NUMERIC_API_v1/Parallel Execution authority, respecting configured workers/core/process limits and existing CPU/RAM/swap policy; no nested or new worker pool is introduced. Existing Unit Registry scene rescaling and semantic history/resource lifecycle remain unchanged.
