# Dataset API audit — dev-059

Dataset identity, canonical payloads and registry entries remain owned by the
existing Dataset authorities. No namespace database, private sidecar store,
viewer-owned geometry engine or alternate publication mechanism was introduced.

| Operation | Reused authority and interface | dev-059 result |
|---|---|---|
| Enumerate/select/inspect/preview | Dataset Catalog, Dataset Selection, Dataset Inspection/Preview, Canonical Dataset and Table Stream APIs | Browser projects catalog namespaces and the existing inspection choice. Catalog namespace projection reads the registry once per snapshot. Preview's historical choice variable aliases the same selection authority. |
| Publish numeric/streamed/file outputs | Dataset Publication v2 and Dataset File Publication v1 | Automatic module namespace; request overrides rejected; owned replacement also requires current namespace ownership; open writers recheck before finalization. Namespace resources roll back with publication. |
| Transform Dataset values | Dataset Transform v1, existing Python/Octave binding | Bridge invokes the existing transform/publication authority inside the actual runtime module context. No alternate transform engine. |
| Ordinary metadata | Dataset Metadata v1 | Reserved `_gxtxt` keys hidden from read/editor/text export; ordinary replacement preserves private fields; writes to reserved keys rejected. Existing public update/unset signatures remain. |
| Module/framework private metadata | Additive functions in Dataset Metadata authority; `private_read/update/unset/owner` in existing Metadata Bridge API | Same canonical INI resource. CORE issues module-bound capabilities; own-prefix writes only, cross-module private reads allowed. Capabilities are not sent over RPC. |
| Organizational namespace | Dataset Namespace v1 backed by reserved metadata and existing Session Manifest | Small semantic interface for normalization, lookup, assigned module namespace and user/admin movement/current namespace. It centralizes policy that ordinary metadata callers must not implement themselves. |
| Schema | Dataset Variable Schema v2/v3 and existing bindings | Bound Tcl and script writes enforce module namespace; existing schema validation/commit and variable identity remain authoritative. |
| Notes | Dataset Notes and Scientific Text APIs | Existing public read/save and GUI reused; bound module writes require assigned namespace. Notes remain their existing resource, not metadata. |
| Rename/delete | Dataset Rename and existing Dataset Delete lifecycle | Existing reference repair, identity/resource cleanup and catalog transactions reused. Bound module writes require assigned namespace. Browser uses those public operations. |
| Dataset ZIP import/export | Portable Resource v1 | Host user/admin import preserves public/private fields and notes, rebinds imported note ownership when the destination ID changes, validates archive integrity and places the Dataset in the target Session current namespace. Export preserves source data. Module output creation uses Publication instead. |
| Legacy import/registration | Existing acquisition/registry commit | Newly registered imports pin the current namespace. Previously saved Datasets without namespace fields continue to display in the Session current namespace. |
| Retained geometry publication/promotion | Existing Native2D Geometry and Primitive Publication APIs over Dataset Publication | Exact composition definition/provenance; explicit finite sampling; actual publishing module determines namespace. Canonical receipt, schema, units and all values are checked before exact reconstruction. |

The namespace API is the only new registered Dataset interface. Private metadata
extends Metadata v1; composition extends Native2D Geometry v1. These public Tcl/
Bridge contracts are additive, so no successor interface or deprecation is
needed. The C Native2D definition structure has additional composition fields;
C consumers must rebuild against the matching header/library. All three shipped
Tcl adapters are rebuilt from the same CORE source. Existing Tcl/script calls and
old Session definitions continue to load.

Python and Octave expose namespace reads and the automatically assigned module
namespace, not user/admin movement or current-namespace changes. Rename/delete,
notes editing and portable import remain host lifecycle/UI operations; this cycle
does not add duplicate RPC operations for them. Existing public Tcl APIs remain
available. Bound Tcl module calls enforce placement for metadata, schema, notes,
rename and deletion as well as publication. A fully trusted in-process Tcl module
is not sandboxed against calling internal procedures or writing files; capabilities
and Bridge context define supported API ownership, not an OS security boundary.

Validation uses actual Python and Octave Script Execution/Bridge journeys, 51
namespace checks, 23 private metadata checks, 18 portable lifecycle checks and the
local Linux browser lifecycle. Injected failures cover registry/sidecar rollback
and an output moved while its writer is open. The browser journey verifies
namespace selection/move, ordinary private-field filtering, notes, ZIP transfer,
current-namespace placement, rename/delete and unchanged source canonical bytes.
