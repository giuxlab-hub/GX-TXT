# Packaging an installable GX-TXT plugin

GX-TXT v0.9.3 can install a plugin directly from the **Modules** tab when its
package contains `plugin-package.ini`.

For a module, distribute for example:

```text
my.analysis/
├── plugin-package.ini
├── module.ini
├── README.md
└── runtime/
    └── my_analysis.m
```

`plugin-package.ini`:

```ini
[package]
api_version=1
id=my.analysis
name=My Analysis
version=1.0.0
type=module
framework_min=0.9.3
framework_max=
```

`module.ini` must use the same ID and version:

```ini
[meta]
api_version=1
id=my.analysis
name=My Analysis
version=1.0.0
kind=analysis
...
```

Zip the package directory if desired. Do not add an install script: installation
is framework-owned and declarative.

For an update, increment **both** `package.version` and descriptor `meta.version`,
then distribute the new package. GX-TXT rejects equal/older versions in Update
mode and refuses to overwrite a directory that was not originally installed by
the package manager.

The same format applies to `model`, `instrument`, and `analysis_definition`
packages, using their normal descriptor filename.

## Packaging several plugins in one ZIP (v0.9.3.2)

Do not merge several descriptors into one artificial plugin. Keep every member
as an independent `plugin-package.ini` package and place them in a
**Plugin Bundle API v1** package set. See `PACKAGING_PLUGIN_BUNDLE.md` and
`../api/PLUGIN_BUNDLE_API_v1.md`.
