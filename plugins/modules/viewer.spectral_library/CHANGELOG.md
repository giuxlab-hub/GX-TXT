## 1.0.15

Declare distinct native-resolution scientific catalog artwork, short title and semantic group through the existing Viewer Provider descriptor.

# Changelog

## 1.0.14

- Honor the library and reference selected in the Scientific Library Manager or Reference Library browser when opening the spectral viewer, including when its window is already open.

## 1.0.13

- Fix Session lookup in optional spectrum and ranking controls. A missing, unrelated or malformed Session Dataset no longer interrupts independent reference-library browsing. Verified installed RefIMP references with no Session and with a measured IR Session in production Tk.

## 1.0.12

- Use public Session Inspection for current-Session and Dataset queries.

## 1.0.11

- Classified the independently packaged module as a managed external plugin.

## 1.0.10

- Added an Install library toolbar action backed by CORE Scientific Library Manager API v1 and the independent IR Library Type Provider.
- Lists compatible managed libraries alongside existing user-authored reference libraries and opens their spectra through the public reference API.
- Shows an explicit empty-library message and preserves existing user-owned libraries when a managed package ID conflicts.

## 1.0.9

- Added a visible versioned library-maintenance dialog for fork, reference metadata or measured-CSV/JCAMP replacement, and user-owned reference removal. Every action uses CORE copy-on-write APIs, preserves the source library, and shows source hash and destination before applying.
- Validated real NIST/PNNL reference fork/update/CSV replacement/removal and the actual Tk Update/Remove buttons in isolated staging. The complete original library hash remained unchanged.

## 1.0.8

- Add a guarded public-source check/install action for the officially published TUM RefIMP curated library. The action stages the rsync download, enforces the audited source SHA-256, invokes the version-pinned CORE adapter, validates the 15-spectrum native library and preserves its portable export. A changed upstream file is retained for audit and cannot overwrite an installed library.

## 1.0.7

- Complete the import preview with a real numerical trace drawn from the parsed source, and correct Treeview refresh after a batch. Verified the GUI with real NIST JCAMP and CSV imports plus an independently failing row.

## 1.0.6

- Add a user-facing CSV/JCAMP-DX import window to the Viewer. Users can choose files or a directory, inspect each source, confirm/edit its spectral interpretation and metadata, choose an existing user-owned library or create a new one, and import files independently with per-file status. This window calls the public CORE Spectrum Import and Reference Library APIs.

## 1.0.5

- Add persistent library → entity/material → spectrum navigation, including entity-filtered search for large scientific libraries.

## 1.0.4

- Permit Session-independent browsing of user-owned reference libraries; Session comparison/ranking controls remain available when a Session is open.

## 1.0.3

- Place Top / Bottom trace labels in the dedicated legend margin so they do not obscure spectral peaks.

## 1.0.2

- Add the required true Top / Bottom split view with shared zoom/pan X and independent Y scales. Overlay now accepts only matching coordinate/intensity semantics and explicitly shape-normalizes comparable traces, avoiding misleading raw transmission-versus-absorption plots.

## 1.0.1

- Corrected the Tk layout and ensured a readable, nonblank three-trace canvas at 1200×760; verified reference search, Session overlay, IR ranking, comparison modes, zoom and persisted reopen against real RefIMP data.

## 1.0.0

- Initial public Viewer Provider for persistent Scientific Reference Libraries and Session spectral comparisons.
