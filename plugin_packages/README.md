# Official dev098 plugin packages

`official_dev098/` contains separately identified Linux candidates for supplied
Curve Digitalizer2.0.3 and optional Scientific Image Inspector0.4.1, with SHA-256
sidecars. The original user archives remain unchanged outside the distribution.
Source provenance and the narrowly necessary Digitalizer adapter correction are
documented in `docs/reports/DEV098_INTEGRATION_AND_EVIDENCE.md`.

Inspector remains core=0/default_enabled=0 and uses the existing Plugin Manager.
Digitalizer retains its supplied bundled CORE descriptor. Exactly the two retired
Viewer IDs have no installed modules or installable ZIP in this distribution.
Other earlier package inventories below are retained historical documentation;
the installed module directories and official_dev098 candidates identify current
sources for the two supplied products.

# Managed plugin packages included with GX-TXT v0.9.3

GX-TXT modules are defined under `plugins/modules/`; the installed descriptors and source files are the authoritative module implementations.

This directory contains selected distributable plugin packages or platform-specific bundles. Plugin installation, validation and upgrades follow the public [Plugin Install API](../docs/api/PLUGIN_INSTALL_API_v1.md) and [Plugin Bundle API](../docs/api/PLUGIN_BUNDLE_API_v1.md).

For package structure and versioning, see the [Plugin Packaging Guide](../docs/guides/PACKAGING_PLUGIN.md).

Generated development packages, historical build artifacts and local installation records are not part of this source distribution. They can be generated separately from the module sources when preparing a release.
