# Project organization — Project API v1 extension

`projectOrganizationApiInfo` describes this additive contract. Its sole durable
authority is `projects.ini`, under Project API v1 and the existing Project /
Experiment Management journal. It is unrelated to Dataset Variable namespaces.

The optional `[organization]` section holds schema
`gxtxt.project_organization.v1`, a monotonic `generation`, and inert dictionary
`namespaces` (stable Project namespace ID → editable name). Each Project record
can hold `namespace_id` and `session_namespaces` (local stable ID → name). Each
Experiment record can hold `session_namespace`. Missing fields mean Ungrouped.
Names are single-line, 1–160 characters, unique without regard to case within
their parent. IDs never depend on names. Default / Unassigned cannot be grouped
and cannot contain named Session groups.

Operations:

- `projectNamespaceList`, `projectNamespaceCreate name ?generation?`,
  `projectNamespaceRename id name ?generation?`,
  `projectNamespaceDelete id ?generation?`.
- `projectNamespaceAssign project namespace ?generation?`; empty namespace
  means Ungrouped Projects.
- `projectSessionNamespaceList project`,
  `projectSessionNamespaceCreate project name ?generation?`,
  `projectSessionNamespaceRename project id name ?generation?`,
  `projectSessionNamespaceDelete project id ?generation?`.
- `projectSessionNamespaceAssign experiment project namespace
  ?expectedProject? ?generation?`; an empty namespace means Ungrouped.
- `projectOrganizationCatalog ?query?` returns one registry-only snapshot with
  generation and stable tree rows. Search includes name, ID, tags, description
  and hierarchy; it never scans scientific payloads.
- `projectOrganizationCapture node` captures stable source identity and
  generation. `projectOrganizationMove capture target` validates and commits.
  Node IDs are Project IDs, `pn:<namespace>`, `sn:<project>:<namespace>` and
  `ex:<experiment>`. Only Projects and Experiments can be move sources.

Interactive moves **must use a captured generation**. A stale source or global
organization generation rejects the entire move. The existing exclusive
transaction journal owns preimages, registry publication and crash recovery.
Its in-memory rollback includes the organization array. No new journal,
registry or filesystem relocation service exists. Group-only changes write
only the registry; cross-Project changes reuse `projectExperimentReassign` and
its existing Session `project_link` update. The group is registry-authoritative
and is not duplicated in scientific Session metadata. Ordinary reassignment
clears the previous Project-local group. Removing a group preserves all its
members in Ungrouped. No Undo is advertised; an inverse move is a new guarded
transaction.

Project Portable carries these optional fields in its existing checksummed
transfer metadata. Import validates all group references and remaps Project,
Experiment, global namespace and local namespace IDs. Equal display names do
not merge namespaces. The receiving installation creates a separately named
imported group when necessary. Old packages remain ungrouped. Scientific IDs,
bytes, origin and source package snapshots retain their existing owners.

The existing Projects page projects this snapshot into one native Treeview.
Search is debounced; rows use no per-Session widgets. Existing action cards
are bounded to 50, while the tree exposes the full registry. Drag targets,
hover expansion, edge autoscroll, Cut/Paste, context actions and inline errors
share the same guarded CORE move. The old public destination dialog remains
available to existing clients, while normal Move routes to the in-page tree.

Acceptance scripts and side effects are registered in `SCRIPT_CATALOG.md`.
