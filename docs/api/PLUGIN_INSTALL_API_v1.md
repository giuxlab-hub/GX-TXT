# Plugin Install API v1 — GX-TXT v0.9.3

## Purpose

Plugin Install API v1 makes a descriptor-driven GX-TXT plugin installable,
updatable, versioned and removable without editing the framework core.

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

Current development packages place `plugin-package.ini`, the normal descriptor,
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
- rolls back the old directory if live discovery fails.

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


## v0.9.3.2 package sets

For one ZIP containing several independent Plugin Install API packages, use
**Plugin Bundle API v1** (`PLUGIN_BUNDLE_API_v1.md`). The bundle layer does not
replace this installer: every live member commit is still performed by
`pluginInstallPackage`.

## Bundled module policy

Bundled modules are updated by GX-TXT framework releases. Plugin Install API manages installable external plugins and modules and intentionally does not overwrite bundled or unmanaged same-ID modules.
