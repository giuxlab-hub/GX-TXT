# Configuration API v1

## Local LaTeX inventory (dev109)

Configuration → Scripts places the read-only LaTeX environment directly after
the existing Python environment. Refresh inspects actual native tool versions,
TeX search roots and installed package/class/font filenames. It requires no
Session, performs no package installation or document compilation, and reports
resource presence separately from successful project compilation. Search shows
at most 500 matching rows from the bounded 20,000-entry inventory.

The existing managed auxiliary request owns the inventory worker and native
version/search child process group. Cancel, refresh replacement and panel close
retire that request; old generation callbacks cannot replace newer observations.
Changing `runtime.latex` invalidates the previous rows and requires Refresh.
Completion verifies the current configured executable and retires its request
even when stale. Session changes alone do not invalidate a machine inventory.
Missing runtimes and launch failures are visible panel diagnostics. This source
contract requires separate real GUI/cancellation evidence; it is not acceptance
of the LaTeX authoring Viewer or every installed TeX resource.

`libraries.scientific_root` remains the persisted GX-TXT Library Root field.
Managed scientific libraries live under its effective value. Consumers can
query that value through the public CORE
`::GX::ScientificLibraryManagerAPIv1::libraryRoot` method. The
`GXTXT_SCIENTIFIC_LIBRARY_ROOT` variable remains an internal compatibility
compatibility mechanism, not a public consumer contract.

GX-TXT separates framework facts, user defaults, module defaults, Session configuration, and runtime state. `configurationFields` returns the registered fields and their scope. `configurationGet` reads a field, `configurationSet` changes a writable value in memory, and `configurationSave` persists user and module defaults to the user's GX-TXT configuration directory.

The configuration file is `configuration.ini` beside the existing Working Directory Profiles file. Only `user` and `module` fields are persisted there. Session manifests remain the authority for Session-specific values; `framework` and `runtime` fields are read-only; Session fields are edited in the scoped Modules editor. An invalid saved user value falls back to its declared default and is recorded in `configurationWarnings` so startup remains usable.

Simple module defaults can be declared in a module descriptor:

```ini
[config]
fields=example

[config.example]
label=Example value
type=string
default=initial
persistent_default=1
```

The field appears in the Configuration page's Modules section and supplies the initial `moduleCfg` value for a new Session. A saved Session's own module configuration still takes precedence when opened. Scalar fields use the complete UI Field type system. Tables and structured settings use the shared rich editors described below.

The built-in configuration fields cover Session and Project root, temporary/cache/export paths, runtime executable preferences, parallel worker policy, user script-library root, and Dataset viewer associations. Viewer associations use Tcl argv-prefix lists such as `{gio open}`; the Dataset path is appended by the framework without shell interpolation. `auto` uses the detected system application. Dataset Preview resolves a viewer primarily from the Dataset's contract, format, and media type, with extension fallback.

`runtimeToolResolve` chooses a configured executable or detects one. On Windows, detection checks the supported runtimes inside a sibling installation directory before the process PATH. `runtimeToolStatus` probes the tool's version, and the Runtime page provides Detect and Test actions. Standard Octave workflows use the existing `cfg(octave_cmd)` integration. Audio Decode, Dataset Preview, plot thumbnails, PDF composition validation, plot annotations, the Scientific Library Manager and the bundled PDF/image Acquisition Handlers resolve their external tools through this service. Configurable tools include Octave, Python, FFmpeg, FFprobe, Tesseract, SPICE, MPI, ImageMagick, pdftoppm, MuPDF and QPDF. The user-configured managed scientific-library path is passed to the Scientific Library Manager through `GXTXT_SCIENTIFIC_LIBRARY_ROOT` before operations; without it, the manager retains its XDG default.

Appearance user defaults and lifecycle are documented in [GUI Appearance](GUI_APPEARANCE_v1.md). Theme/font settings are applied once at GUI startup; popup recovery is applied immediately after Save.

## Central and module-local configuration

Configuration → Modules exposes every installed Module's declared `[config]`
fields and formally registered module-owned public fields, including disabled
and always available providers. Discovery runs at catalog load; it does not
activate a Viewer or scientific module. Packages without a schema say so.
Metadata, documentation, search and Plugin Manager remain available.

`configurationModuleFields module_id` returns an ID→descriptor dictionary from
this same registry. Descriptor fields retain `module_id`, `module_key`,
`module_type`, `scopes`, `application`, bounds, choices and validation callbacks.
`configurationModuleDiscover module_id` reconciles the installed descriptor.
A formal `configurationRegister` includes the same ownership attributes; its
`module_key` participates in the existing Manifest lifecycle even if registered
later. Stable field IDs and valid saved values survive rediscovery. Invalid
schema upgrades are reported in `configurationWarnings`. Unregistered saved
keys are preserved for disabled or temporarily unavailable packages.

Precedence is factory → persisted User default → explicit Session override.
`persistent_default=1` supports `scopes={user session}`. Ordinary descriptors
retain Session-only scope; they are not silently promoted into global defaults.
An absent persistent field in a Session manifest means inheritance, whereas a
present value (including an explicit empty optional value) means override.
Legacy manifests with values retain their overrides. Table rows remain owned
by Repeatable Config and its existing Session sections. Resource bindings remain
owned by their Dataset/Selection/Model/Temporal Set authorities.

```tcl
set id module.example.configuration.level
set receipt [::GX::configurationResolve $id]
# factory, user, override, effective, origin, scopes, session_token
set starting [::GX::configurationScopedValue $id user]
::GX::configurationCommit [list [dict create id $id scope user value 5 expected $starting]]
# Explicit override, bound to the actual Session lifetime, including A→B→A:
set receipt [::GX::configurationResolve $id]
::GX::configurationCommit [list [dict create id $id scope session value 7 \
    expected [dict get $receipt effective] session_token [dict get $receipt session_token]]]
# clear=1 removes that override and inherits the current User default.
```

`configurationCommit changes ?persist=1?` validates every candidate, typed bounds,
module validators, scope, readonly status, expected current values and Session
lifetime before mutation. User and Session durable transactions are separate.
User defaults use the existing atomic `configuration.ini` replacement. Session
changes use atomic replacement of the existing Manifest, with rollback of live
module/repeatable state on failure. `expected` is a compare-before-commit value,
not a revision invented by the editor. Conflicting editors retain drafts and
report an error; explicit Reload / discard is the GUI resolution.

`configurationSubscribe callback` returns a subscription ID; the callback takes
one field ID (empty means lifecycle refresh). `configurationUnsubscribe id`
releases it. Successful registrations and commits notify projections; subscriber
failures cannot undo or misreport a committed transaction. `configurationSet`
continues its memory-only contract and updates inherited effective module values.

`application=immediate|next_invocation|restart` describes the module's lifecycle.
Immediate consumers subscribe and read `configurationResolve`; next-invocation
consumers read at invocation; restart settings apply at startup. CORE never
executes plugin-specific behavior. Existing module-local `moduleCfg` controls
write Session overrides; global defaults continue to use this registry.

The shared GUI client is `configurationModuleDialog module_id ?parent=.?`.
Both surfaces use the same typed descriptors, validators, conflict checks and
commit operation. The arrays in `ConfigurationEditor` are transient drafts only.
Late registration refreshes clean projections and preserves dirty drafts. The
ordinary Save user defaults page reads drafts only from fields backed by editors
on the current page. Hidden fields retain their current CORE values even if a
stale Tk array entry remains from an earlier projection. Printer observations,
project presentation state and independently saved source schemes are preserved.
Appearance, Source Surface palette/highlighting and Native3D keep their existing
editor bindings; Resource Management owns the cache policy.

### Module-owned structured editors

A lightweight `[configuration] entrypoint=api/settings.tcl` contributes only
schema/validation procedures. A field can declare `configuration_id` (stable
legacy ID), `validator` (command prefix receiving and returning the whole
normalized value), `structured_fields` (command prefix returning UI Field
member descriptors), `choices_provider` (command prefix returning values),
`description`, `readonly`, `visible`, and `application`.
These callbacks must not launch the module or create a second persistence store.
Discovery validates that the entrypoint stays inside its installed module root.
A structured editor validates the whole dictionary before staging, then commits
through Configuration like any scalar field. Workbench shortcuts use this
contract and their module-owned command schema/conflict validator.

The installable descriptor-only example at
[`docs/examples/module_configuration`](../examples/module_configuration/README.md)
contains integer/choice/boolean settings and a typed Session table. It works in
both interfaces without any CORE or global GUI edits for its module ID.

Open rich forms capture the same expected value and Session lifetime as scalar
drafts. Applying a form after another editor changes that field rejects its stale
write and retains the form contents. Session A→B→A invalidates old Session drafts.
Catalog refresh preserves forms and dirty projections; explicit Reload resolves
conflicts. Formally registered module fields also participate in Manifest
persistence even when they are not statically listed in `[config]`.

Binding types (Dataset, Variable, selection, temporal set, registered script,
analysis definition, model and unit) validate through their existing public
authorities at commit. Discovery does not require scientific runtime data.

## Generic Viewer command adapter

The existing Configuration/UI owner now supplies `viewerCommandCatalogRegister
catalog_id commands ?configuration_id? ?module_key? ?owner_module?`. Each stable command descriptor
has `label`, optional `default` key, and a keyboard `scope` (default `viewer`).
An optional `context` predicate receives the focus widget. Lightweight module
configuration contributions register catalogs without opening their Viewer.
`viewerCommandCatalog`, `viewerShortcutsValidate`, and `viewerShortcutFields`
expose the same discoverable catalog and typed dictionary editor.

`viewerCommandsAttach window module handlers ?guard? ?widgets?` binds runtime
callback prefixes. Handlers have `command` and optional `enabled` predicate;
the common guard and Session lifetime apply to mouse and keyboard alike.
`viewerCommandMenuAdd` creates an entry and `viewerCommandMenuTrack` associates
an existing entry. `viewerCommandMenusRefresh` updates live enablement and
accelerators. `viewerCommandInvoke` executes only enabled commands;
`viewerCommandsDetach` releases bindings and subscriptions (also on Destroy).
Window scopes are independent. Entries, text, comboboxes and dialogs retain
native editing/navigation; command keys do not invoke scientific operations
while those controls have focus. Conflicts within a declared scope and reserved
keys reject the complete Configuration transaction. User defaults and Session
overrides keep the ordinary Configuration precedence and atomic persistence.

Curve Workbench retains `modules.curve_workbench.shortcuts` and all established
command IDs/defaults. Its existing catalog/editor/menu and scientific callbacks
delegate key normalization/dispatch to CORE without resetting saved values.
These host operations use the existing Configuration authority and its
preference storage. The unknown-Viewer fixture demonstrates use
without a CORE branch for any module ID.

## Selective presentation persistence

The existing `configurationSave ?fields? ?apply=1?` defaults preserve its full-save
behavior. A nonempty list limits persistence to those registered User/module
fields; other previously saved values remain intact and unrelated pending values
are not committed. `apply=0` writes through the same atomic Configuration owner
without reapplying runtime, storage or resource defaults. Runner view preferences
use `{scripts.job_presentation} 0`; they never own or configure Job execution.


## Plugin package chooser and Script Workspace visibility

`plugins.package_chooser_directory` is a User-scoped path in Configuration →
Modules, labelled **Default plugin package directory**. It supplies only the
initial directory of the shared Install/Update/Bundle chooser. A missing or
inaccessible directory falls back safely; `storage.package_dir` and actual
managed installation targets remain independent.

The existing User boolean `features.script_workspace` appears in Configuration →
Scripts as **Show Script Workspace in Analysis**. Saving changes refreshes the
optional **Scripts (CORE)** Analysis panel. Its identity, default and saved value
remain unchanged. It neither disables Python/Octave modules nor changes Script
Bridge, Job execution, or the separate main Modules-page surface controls.

A module with multiple Viewer command catalogs can declare a distinct logical `catalog_id` and its actual installed `owner_module`. Shortcut IDs/scopes remain distinct; authenticated command callbacks run under the real module identity. The optional owner defaults to the catalog ID for existing consumers. Surface Fit uses its separate catalog with `owner_module=viewer.dataset_curve_fit`; this does not create a synthetic module or weaken Metadata/Publication actor checks. Toolbar mounting honors the requested command order while retaining the same command IDs and enablement predicates.

Configuration → Execution stores compute-node descriptors and destination selection through the same User fields. Configuration → Modules separates Services from Viewer presentation management. Provider flags persist independently from Analysis Run membership; disabling presentation preserves required scientific services and active Workspaces. Sessions → Preview Cache manages only disposable derived representations; its policy uses ordinary Configuration fields.

Viewer command catalogs may use a logical catalog identity distinct from the
installed module that owns their callbacks. `viewerCommandCatalogRegister
catalog_id commands ?configuration_id? ?module_key? ?owner_module?` records that
explicit installed owner for Configuration registration and authenticated command
invocation. Omitting the owner retains the catalog identity as owner. This keeps
multiple catalogs/shortcut fields for one module within the same existing command
authority, including Surface Fitter. It does not register another module.

Dev109 adds `::GX::configurationOpenPage page` (`open_page`) for ordinary GUI
navigation to an existing Configuration page: storage, runtime, computation,
execution, libraries, scripts, viewers or modules. It changes no values and
requires the main GUI to be open. Restricted C++ Viewers can request only the
fixed Runtime destination through `Host::em_command(form, "runtime")` with the
explicit `CONFIGURATION_API_v1/open_page` grant; no widget path enters the SDK.

The Scripts page shares its available height between the existing Python and
LaTeX inventory panels. Each panel keeps its own scrollable tree and controls;
resizing the page does not change configuration values or restart inventory.
