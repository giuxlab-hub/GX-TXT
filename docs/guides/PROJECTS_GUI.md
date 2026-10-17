# Projects GUI

The existing Projects page is a hierarchical navigator over Project API v1:

```
Project namespace
  Project
    Session namespace
      Session / Experiment
    Ungrouped
Ungrouped Projects
Default / Unassigned
```

Use native drag-and-drop or Cut → select/search destination → Paste. A Project
can move to a Project namespace; a Session can move to a Project or one of its
local Session groups. The CORE transaction validates source membership and
organization generation before publication. Stale or invalid targets produce
an inline explanation. Paths and scientific contents remain intact.

Create, rename and remove namespaces in the compact editor. Removal preserves
members in Ungrouped. Default / Unassigned stays protected. Project creation,
metadata editing, scientific inspection, import/export and destructive Session
operations keep their established controllers and confirmations.

The tree supports large registries without one widget per Session. Search
shows matching entries with ancestors, counts and breadcrumbs. The right side
shows metadata and quick actions; scientific Info is an explicit request.
The action-card overview is bounded to 50 entries while the tree exposes all
entries. Selection, expansion and scrolling use user Configuration preferences.

Project Portable carries grouping metadata and remaps organizational IDs on
import. Scientific Dataset IDs, payload bytes and declared creator retain their
existing portable contracts. Predecessor packages remain Ungrouped.

See [Projects help](../help/projects.md) and
[Project organization API](../api/PROJECT_ORGANIZATION_v1.md).
