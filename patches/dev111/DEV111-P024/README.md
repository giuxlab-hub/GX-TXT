# GX-TXT DEV111-P024 — Native Workspace and Scientific Session Integration

## Italiano

**DEV111-P024 — Workspace nativo e integrazione delle Session scientifiche**

Introduce un Workspace nativo condiviso per Viewer scientifici, Script, Document e risorse persistenti delle Session.

### Funzionalità
- Aggiunge il motore Workspace nativo C++, l'integrazione Tcl e le API pubbliche NATIVE_WORKSPACE_API e VIEWER_WORKSPACE_SDK.
- Coordina Workspace dei Viewer, associazioni ai Document, comandi, selezione, History e transizioni del ciclo di vita.
- Estende persistenza del Session Workspace e trasporto portabile delle risorse scientifiche e delle configurazioni dei Viewer.
- Collega gli Script Python e Octave alle API condivise Workspace e Session.
- Aggiorna gli strumenti scientifici per riutilizzare i servizi Workspace condivisi, inclusi Curve Workbench, Digitizer, plotting, 3D Workbench ed editor Script.
- Comprende binari nativi, sorgenti corrispondenti e documentazione delle API nell'archivio incrementale.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P023` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P024.zip` (SHA-256: `e9f8d96bb8da44d7339f6e5e15a411dc5eae81c980b9c2deb68f762e86f169c3`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P024)

## English

**DEV111-P024 — Native Workspace and Scientific Session Integration**

Introduces a shared native Workspace foundation for scientific Viewers, Scripts, Documents and persistent Session resources.

### Features
- Adds the native C++ Workspace engine, Tcl integration and public NATIVE_WORKSPACE_API and VIEWER_WORKSPACE_SDK contracts.
- Coordinates Viewer workspaces, scientific Document associations, command state, selection, History and lifecycle transitions.
- Expands Session Workspace persistence and portable import/export support for scientific resources and Viewer configurations.
- Connects Python and Octave Script bindings with the shared Workspace and Session APIs.
- Updates scientific tools and Viewers to reuse shared Workspace facilities, including Curve Workbench, Digitizer, plotting, 3D Workbench and Script editing.
- Includes native binaries, matching source and API documentation in the incremental patch.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P023`, according to the bundled README.

Original archive: `DEV111-P024.zip` (SHA-256: `e9f8d96bb8da44d7339f6e5e15a411dc5eae81c980b9c2deb68f762e86f169c3`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P024)
