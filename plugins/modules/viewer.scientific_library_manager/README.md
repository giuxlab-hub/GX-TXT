# Scientific Library Manager

Open `viewer.scientific_library_manager` from Viewers. The manager lists the Library Type Providers registered by installed modules and the scientific data libraries installed in managed storage. Filter by type or library name, inspect version, source, license, package and payload hashes, then install, verify, update, remove or open a library.

The manager calls `SCIENTIFIC_LIBRARY_MANAGER_API_v1`; provider modules validate scientific content. It does not interpret IR or NMR data. The provider advertises the appropriate viewer for the Open action. Selecting a reference before **Open / use** opens that reference in the IR or NMR viewer. Installed-library state is stored by CORE in the managed scientific-library registry.

The IR-specific management interface in `viewer.spectral_library` and the `viewer.reference_library` browser remain available.
