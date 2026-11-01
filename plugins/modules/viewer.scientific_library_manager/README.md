# Scientific Library Manager

This Viewer is deprecated in favor of **Scientific Libraries**, the unified Builder-authored management Viewer. It has no normal catalog tile. Saved Viewer-open references and direct compatibility routes remain supported.

Open the preserved `viewer.scientific_library_manager` route when compatibility requires it. The manager lists the Library Type Providers registered by installed modules and the scientific data libraries installed in managed storage. Filter by type or library name, inspect version, source, license, package and payload hashes, then install, verify, update, remove or open a library.

The manager calls `SCIENTIFIC_LIBRARY_MANAGER_API_v1`; provider modules validate scientific content. It does not interpret IR or NMR data. The provider advertises the appropriate viewer for the Open action. Selecting a reference before **Open / use** opens that reference in the IR or NMR viewer. Installed-library state is stored by CORE in the managed scientific-library registry.

The IR-specific management interface in `viewer.spectral_library` and the `viewer.reference_library` browser remain available.

This deprecated management Viewer is available through deliberate saved/direct routes and explicit legacy inventory. It has no normal launcher tile, including when Scientific Libraries presentation is disabled.
