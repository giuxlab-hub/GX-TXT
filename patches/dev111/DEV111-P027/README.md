# GX-TXT DEV111-P027 — Multifile C++ Viewers, Preview Builder and Typed Script Runner

## Italiano

**DEV111-P027 — Viewer C++ multifile, Preview Builder e Script Runner tipizzato**

Estende lo sviluppo Viewer C++ ai progetti multifile, introduce l'authoring Dataset Preview, unifica le librerie scientifiche e l'esecuzione degli Script tipizzati.

### Funzionalità
- Supporta progetti Viewer C++ con più unità di compilazione e header locali, editor a file/albero/schede, Save All, manifest di build, debug e import/export portabile.
- Estende Viewer Interface Builder alla creazione di provider Dataset Preview reali (kind=preview, runner=service, gui_api_version=1) con controlli e ciclo di vita standard.
- Consolida Scientific Libraries in un Viewer C++ principale sviluppato col Builder, con ricerca, filtri, paginazione, provenienza e registrazioni esterne.
- Utilizza uno Script Runner condiviso tra percorsi Python e Octave, conservando Dataset ID, revisione, contesto e proprietà di ciascun input.
- Introduce parametri Script tipizzati e Save/Load esplicito dei Dataset canonici con schema, Variable ID, integrità e provenienza.
- Aggiorna SDK di sviluppo, binding Script, Catalogo API, moduli e manuali; conserva la compatibilità dei Viewer C++ a file singolo.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P026` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P027.zip` (SHA-256: `445c0185fa68dd8d53217b8cff25a151ee20c747cb95666576ff87bf8dc73046`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P027)

## English

**DEV111-P027 — Multifile C++ Viewers, Preview Builder and Typed Script Runner**

Extends restricted C++ Viewer Development with multifile projects, adds Dataset Preview authoring, consolidates Scientific Libraries and unifies typed Script execution.

### Features
- Supports C++ Viewer projects with multiple translation units and local headers, file/tree/tab editing, Save All, exact build manifests, debugging and portable import/export.
- Extends Viewer Interface Builder to author real Dataset Preview providers (kind=preview, runner=service, gui_api_version=1) with standard lifecycle and UI controls.
- Consolidates Scientific Libraries into one primary Builder-authored C++ management Viewer with search, filtering, paging, provenance and external registrations.
- Uses one shared Script Runner across Python and Octave routes, preserving each input Dataset ID, revision, context and ownership.
- Adds typed script parameters and explicit canonical Dataset Save/Load with schema, Variable IDs, integrity and provenance.
- Updates development SDK, script bindings, API catalog, modules and documentation; preserves existing single-file Viewer compatibility.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P026`, according to the bundled README.

Original archive: `DEV111-P027.zip` (SHA-256: `445c0185fa68dd8d53217b8cff25a151ee20c747cb95666576ff87bf8dc73046`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P027)
