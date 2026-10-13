# Plugin Bundle / Package Set API v1 — GX-TXT v0.9.3.2

## Purpose

Plugin Bundle API v1 installs a **set of ordinary Plugin Install API v1 packages
as one atomic operation**. It exists for tools that are distributed as several
independent plugins, for example one analysis module plus a family of
mathematical-model plugins.

It is deliberately **not a second installer**. Every bundle member must already
be a valid `plugin-package.ini` package, and live installation of every member
is delegated to the existing `pluginInstallPackage` implementation.

A bundle therefore adds only:

- one bundle descriptor;
- package-set validation;
- all-member preflight/staging;
- transaction/rollback;
- optional bundle provenance in the normal managed-plugin registry.

## Layout

Recommended ZIP layout:

```text
curve_family_parameter_model_bundle.zip
├── plugin-bundle.ini
└── packages/
    ├── curve.family_parameter_model/
    │   ├── plugin-package.ini
    │   ├── module.ini
    │   └── ...
    ├── parameter-law.constant/
    │   ├── plugin-package.ini
    │   ├── model.ini
    │   └── ...
    └── parameter-law.linear/
        └── ...
```

The bundle may be installed from a directory, a selected `plugin-bundle.ini`, or
one ZIP containing exactly one `plugin-bundle.ini`.

## Descriptor

Minimal descriptor:

```ini
[bundle]
api_version=1
id=curve.family_parameter_model
name=Curve Family Parameter Model
version=1.0.0
framework_min=0.9.3.2
framework_max=

[packages]
paths=packages/curve.family_parameter_model;packages/parameter-law.constant;packages/parameter-law.linear
```

Required:

- `bundle.api_version=1`
- stable `bundle.id`
- `bundle.version`
- one or more relative `packages.paths`

Optional:

- `bundle.name`
- `bundle.framework_min`
- `bundle.framework_max`

Each path must be relative to the bundle root and must name a directory that is
itself a valid Plugin Install API v1 package root.

## Transaction contract

`pluginInstallBundle` performs the following sequence:

```text
open bundle
    ↓
validate bundle descriptor
    ↓
validate every plugin package
    ↓
preflight every destination / conflict / version
    ↓
stage every package
    ↓
snapshot affected live targets + installed.ini
    ↓
commit members through pluginInstallPackage
    ↓
final discovery + registry provenance
    ↓
success
```

If any member commit, final discovery, or registry write fails:

```text
failure
  ↓
restore every affected plugin directory
restore exact pre-bundle installed.ini
reload discovery
  ↓
error returned to caller
```

The API never intentionally leaves a partly installed bundle.

Pre-staging all members before the first live commit also prevents a source
folder from changing halfway through the operation.

## Public Tcl entry points

Install a package set:

```tcl
::GX::pluginInstallBundle /path/to/bundle.zip install
```

Automatic GUI/package dispatcher:

```tcl
::GX::pluginInstallAny /path/to/source install
```

`pluginInstallAny` detects a bundle and otherwise delegates to
`pluginInstallPackage`.

The implementation also accepts the base installer modes `update` and `auto`,
but v0.9.3.2 exposes only **installation of a bundle** as a standard GUI flow.
Bundle-level Update/Uninstall actions are intentionally deferred.

## Registry

Bundle members remain ordinary entries in:

```text
plugins/.registry/installed.ini
```

No separate bundle registry is required in API v1. A member installed from a
bundle additionally records:

```ini
bundle_id=curve.family_parameter_model
bundle_version=1.0.0
```

The ordinary plugin ID, type, version, timestamps and source-package fields are
retained.

## GUI

The existing **Modules → Install plugin...** action now accepts both:

- a single Plugin Install API v1 package;
- a Plugin Bundle API v1 ZIP/package set.

For a bundle the success dialog reports the bundle ID, version and number of
installed member packages.

`Managed plugins...` shows bundle provenance for member plugins. Bundle-level
Update/Uninstall controls are not part of v1.

## Security

Bundle handling inherits all Plugin Install API restrictions and adds package-set
validation:

- no absolute package paths;
- no `..` traversal;
- no symlinks;
- ZIP entries are checked before extraction;
- every member must pass its own `plugin-package.ini` validation;
- duplicate plugin IDs/targets in one bundle are rejected;
- unmanaged live plugins are never overwritten;
- all conflicts are checked before the first member commit;
- no bundle or member install scripts are executed.

Runtime privileges of installed plugins are unchanged.

## Non-goals in v1

Not included:

- online repositories;
- automatic downloads;
- dependency resolution between bundles;
- cryptographic signatures;
- bundle-level Update button;
- bundle-level Uninstall button;
- a second package registry;
- private installer scripts.
