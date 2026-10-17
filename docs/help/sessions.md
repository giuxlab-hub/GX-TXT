# Sessions

A Session is the portable record of one experiment or analysis workflow. Its `metadata/manifest.ini` stores Session configuration; `metadata/datasets.ini` indexes canonical Datasets. Source files, notes, registered Session scripts, analysis outputs and Viewer state remain inside the Session.

Create a standalone Session under the configured storage root, or create one inside a Project. Project membership uses stable IDs and does not move an existing Session. Click the Session path in the main bar to locate it.

Use the Sessions browser to inspect Session files and registered scripts. Session scripts are physical snapshots: editing a reusable user script later does not silently alter the Session copy.

See [Datasets](datasets.md) and [Scripting](scripting.md) for the content stored in a Session.

## Portable individual resources (dev-051)

Whole Session export remains separate from Dataset ZIP and Graph ZIP. Dataset ZIP transfers one scientific Dataset; Graph ZIP transfers one graph and its declared dependencies into a new Clone. The import review reports source identity, SHA integrity, dependency collisions and available scientific/rendered reconstruction. See [resource ZIP guide](../guides/PORTABLE_RESOURCE_EXPORT_IMPORT.md).

## Instrumentation section (dev081)

The existing Session navigator includes **Instrumentation**, alongside Experiment,
Workspaces and Session Parameters. Its browser selects a Session instrument; the
right canvas hosts the original editor or the embedded Instrument Library. Use the
new **Instruments** menu for Add Instrument… and Open Library…. The former separate
Instrumentation tab and Import / Export toolbar menu are removed.

**Tools → Export Session… / Import Session…** preserve the existing portable Session
workflow and provider actions. **Configuration** still contains configuration-only
INI export/load. Session instrument view changes retain live edits; leaving the
Session offers Save/Discard/Cancel, and Save configuration saves instrument notes too.
See [Instrumentation](instrumentation.md) for Library and snapshot behavior.

Since dev082, Configuration / Manifest includes a full Session-private Storage Profiles
manager. Since dev083, every Session has a named or Default Project; Projects adds
stable row actions and lossless Portable import/export. See Storage Profiles and Projects help.

## Session groups in Projects

A Project may have named Session namespaces. Use Projects to drag a Session into
a group, or Cut it, select/search a destination and Paste. Moving between
Projects chooses Ungrouped unless a destination group is selected. These are
organizational groups; scientific Variable namespaces and Session directories
retain their identities. See [Projects](projects.md).
