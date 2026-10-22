# Plugin Install API v1

## Purpose

Plugin Install API v1 makes a descriptor-driven GX-TXT plugin installable,
updatable, versioned and removable without editing the framework core.

Dev109 preserves ordinary ALWAYS-module and CORE uninstallation protection.
An independently installed Library Type Provider with actual descriptor
`[library_type_provider] api_version=1` and `runner=service` may be uninstalled
even though `selectable=0` keeps it out of runnable Analysis choices. It still
must be managed, non-CORE and removed through this same Plugin Install owner;
its registry references can then truthfully report provider unavailable. This
exception does not make other ALWAYS modules removable or delete scientific
library registrations/payloads as an implicit side effect.

The plugin author adds one file to the package root:

```text
plugin-package.ini
```

The package is data-only. The framework **never executes an installer script**.
The installation destination is derived from `package.type` and `package.id`;
a package cannot request an arbitrary filesystem path.

## Package descriptor

Minimal module example:

```ini
[package]
api_version=1
id=example.analysis
name=Example Analysis
version=1.2.0
type=module
framework_min=0.9.3
framework_max=
```

Required keys:

- `api_version=1`
- `id`: stable plugin ID; `[A-Za-z0-9._-]` only
- `version`: plugin/package version
- `type`: `module`, `model`, `instrument`, or `analysis_definition`

Optional keys:

- `name`
- `framework_min`
- `framework_max`

The normal GX-TXT descriptor must be at the package root and its `meta.id`,
`meta.version`, and `meta.api_version` must agree with `plugin-package.ini`.

| package.type | Required descriptor | Install root |
|---|---|---|
| `module` | `module.ini` | `plugins/modules/<id>/` |
| `model` | `model.ini` | `plugins/models/<id>/` |
| `instrument` | `instrument.ini` | `plugins/instruments/<id>/` |
| `analysis_definition` | `analysis.ini` | `plugins/analysis_definitions/<id>/` |

## Package forms

The API accepts:

1. a package directory;
2. a selected `plugin-package.ini`;
3. a `.zip` containing exactly one `plugin-package.ini`.

ZIP entries are checked before extraction. Absolute paths, drive-rooted paths,
`..` traversal and symbolic links are rejected.

Portable packages place `plugin-package.ini`, the normal descriptor,
and payload files directly at the ZIP root. The installer still accepts a single
enclosing directory for older packages, but new packages use the root layout.

## Install and update semantics

`pluginInstallPackage source install`

- requires the target ID to be absent;
- validates the package and ordinary GX-TXT descriptor;
- stages the package under the plugin tree;
- switches it into place only after validation;
- reloads normal GX-TXT discovery;
- records it in `plugins/.registry/installed.ini`.

`pluginInstallPackage source update expected_id`

- requires a Plugin-Install-API-managed plugin with the same ID;
- requires a version newer than the installed version;
- performs a staged replacement;
- restores the exact previous package and registry if discovery, registry commit or certified activation fails.

`auto` mode installs an absent plugin or updates an existing managed plugin;
downgrades are rejected.

Existing bundled/unmanaged directories are never overwritten.

## Uninstall

```tcl
::GX::pluginUninstall module example.analysis
```

Only plugins recorded as managed by this API can be removed. Uninstalling a
plugin removes its installed plugin directory and registry entry. It does **not**
delete datasets, notes, manifests, plots or previous session results.

A plugin whose normal descriptor declares `[meta] core=1` is additionally protected: it cannot be uninstalled even if it appears in installation metadata. CORE status is independent from runtime enablement and `default_enabled`.

## Managed plugin registry

Framework-owned registry:

```text
plugins/.registry/installed.ini
```

It stores at least:

- stable ID;
- type;
- installed version;
- name;
- first installation timestamp;
- last update timestamp;
- source package filename.

This registry is installation metadata, not scientific session metadata.

## GUI

Open the existing single **Plugin Manager** through **Configuration → Modules →
Plugin Manager…**. It provides Install, Update selected and Uninstall selected for
managed module, model, instrument and analysis-definition packages. Installation
continues to accept standalone packages and bundles. Updating requires a managed
selection; removal additionally excludes CORE and ALWAYS modules. The normal
Configuration browser retains installed-plugin inspection and documentation.

The live **Filter plugins** field matches actual ID, name, type, version and
bundle text without changing the registry. Reset or Escape clears the filter.
A row that remains visible keeps its selection; a hidden row clears selection
and disables Update/Uninstall. Installed and active implementation versions are
separate columns. Select a row to inspect its complete activation status below
the table; horizontal scrolling and window resizing expose all columns.

**Configuration → Modules → Default plugin package directory** is a User
preference shared by Install, Update and bundle package choosers. Browse selects
an existing directory; typing a missing/inaccessible directory safely falls back
to the user's home directory (then current directory if needed). Saving this
preference never changes installation targets or framework package storage.

The main **Modules** page selects membership in Analysis. It has no plugin
administration actions. CORE is a distribution/protection class independent from
runtime enablement; the quick Plot, Script Octave and Script Python controls
explicitly select those three optional CORE surfaces.

## Security rules

A conforming package:

- cannot select an arbitrary target path;
- cannot install outside the matching `plugins/<type>/<id>/` root;
- cannot contain symbolic links;
- cannot use ZIP path traversal;
- cannot execute pre/post-install code;
- cannot overwrite an unmanaged/bundled plugin;
- must pass ordinary descriptor discovery before an update is committed.

Plugin runtime code is still subject to the normal GX-TXT execution model; the
Install API does not grant additional runtime privileges.


## Package sets

For one ZIP containing several independent Plugin Install API packages, use
**Plugin Bundle API v1** (`PLUGIN_BUNDLE_API_v1.md`). The bundle layer does not
replace this installer: every live member commit is still performed by
`pluginInstallPackage`.

## Bundled module policy

Bundled modules are updated by GX-TXT framework releases. Plugin Install API manages installable external plugins and modules and intentionally does not overwrite bundled or unmanaged same-ID modules.


## Runtime activation and safe updates

The host-only `pluginRuntimeInfo plugin_id` reports `installed_version`,
`active_version`, `status` and explanatory `reason`. Update receipts contain the
same fields. The Manager distinguishes **Updated and active**, **Updated —
restart required**, and **Update failed**. A new or never-loaded implementation
uses its normal lazy loader immediately. A loaded Tcl implementation without a
certified lifecycle remains active and requires a framework restart; another
entrypoint cannot silently mix the newly installed code with the old runtime.
Its previous package is retained outside descriptor discovery while pending.

An active Analysis computation, a cooperative Acquisition, any durable active Script Job, a loaded native
library from the affected plugin, or a live framework child worker prevents
replacement. The operation reports failure and explains what must finish or be
closed. No native library is hot-unloaded and no worker or scientific Job is
cancelled by an update. The durable Job owner's complete active lifecycle is
used, independently of table pagination or hidden terminal entries.

Descriptor-declared Acquisition adapters use the same loaded-version and
pending-restart lifecycle. The complete loaded callback/capability registration
remains together during catalog refresh; new descriptors do not rewrite the old
registration. A pending update rejects subsequent Acquisition loader/inspect/import
entrypoints until restart. Partial Tcl source failures are conservatively counted
as loaded code. A fresh process loads the installed adapter normally; CORE does
not blanket-source a replacement adapter in the old interpreter.

A pure Tcl provider can opt into its own certified process-local lifecycle while
its public API is activated under CORE's existing module context:

```tcl
::GX::pluginLifecycleRegister $module_id ::MyModule::lifecycle
```

The command prefix accepts these host operations:

- `prepare_update`: returns a dictionary containing boolean `safe` and optional
  English `reason`. `safe=1` certifies that this provider has no live editor,
  dirty document, native library, worker, callback or scientific operation that
  would be invalidated by rebinding. It must not alter scientific state.
- `activate target_root installed_version`: the provider performs its explicit
  safe removal/rebinding and registers its current API/backend implementation.
  CORE does not guess namespaces, blanket-source entrypoints, or unload code.
- `rollback restored_root previous_version`: restores the previous implementation
  if a transactional activation fails. It must preserve existing scientific and
  Interactive Document state and remain usable after a partial activation error.

Registration is allowed only for the module's current activation identity.
This is a trusted already-loaded provider extension, not a package install
script, a package-declared arbitrary command, or a Script Bridge operation.
Process-local UI/code lifetime has no independent Python/Octave execution
meaning, so these lifecycle operations are host-only.

When a certified provider reports an open editor (`safe=0`), the Manager reports
the installed and still-active versions separately. After its normal Close,
the next Open rechecks the same lifecycle and activates only when it certifies
quiescence. An unsuccessful deferred activation retains restart-required status
with its exact reason and attempts provider-owned rollback; no false activation
success is reported. Hidden old-package backups preserve assets for pending
runtime recovery; scientific resources remain owned by their existing Session
and Managed Resource authorities.

Bundle members use the same installer and exact registry transaction. Loaded
members defer rebinding until the entire bundle commits; rollback never leaves
a newly activated first member behind after a later member fails. Reopening a
quiescent certified provider can activate the committed implementation.
