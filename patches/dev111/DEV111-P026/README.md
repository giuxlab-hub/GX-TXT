# GX-TXT DEV111-P026 — Framework Maintenance, API Catalog and Curve Workbench

## Italiano

**DEV111-P026 — Manutenzione framework, Catalogo API e Curve Workbench**

Aggiunge l'interfaccia Framework Maintenance, il trasporto di Project e Session, il Catalogo API aggiornato e nuovi flussi di persistenza di Curve Workbench.

### Funzionalità
- Introduce la pagina Framework Maintenance in Configuration, organizzata in sette sezioni e collegata ai servizi pubblici competenti.
- Gestisce backup e ripristino portabile di Project/Session, identità delle risorse e Session annidate o non associate.
- Unifica la manutenzione di risorse gestite, moduli opzionali, diagnostica STDERR, impostazioni e Catalogo API.
- Aggiorna il database nativo del Catalogo API e la consultazione delle dichiarazioni, con Refresh/Reconcile controllato.
- Aggiorna menu Workspace Host di Curve Workbench, bozze nominate, Save/Clear, backup protetti e gestione History.
- Aggiorna metadati dei moduli Curve Digitizer e Curve Workbench, documentazione e persistenza scientifica.
- Richiede DEV111-P025-r2; le istruzioni di applicazione e ripristino sono incluse in patch_notes.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P025-r2` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P026.zip` (SHA-256: `a94f534ea4def46cbe665cdf5e1fc8b1ccb1129d732cf09295d0f7a63ae34e2f`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P026)

## English

**DEV111-P026 — Framework Maintenance, API Catalog and Curve Workbench**

Adds the Framework Maintenance control surface, Project and Session transport, updated API Catalog and Curve Workbench persistence workflows.

### Features
- Introduces a seven-section Framework Maintenance page inside Configuration, delegating operations to the corresponding public service owners.
- Provides Project/Session backup, portable restoration, identity mapping and handling of nested or unassociated Sessions.
- Unifies managed resources, optional modules, diagnostic STDERR records, settings and API Catalog maintenance.
- Updates the native API Catalog database and declaration browsing, with controlled refresh/reconciliation.
- Updates Curve Workbench shared Workspace Host menus, named drafts, Save/Clear semantics, protected backups and History ownership.
- Updates Curve Digitizer and Curve Workbench module metadata, documentation and scientific persistence integration.
- Requires DEV111-P025-r2; application and rollback instructions are included in patch_notes.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P025-r2`, according to the bundled README.

Original archive: `DEV111-P026.zip` (SHA-256: `a94f534ea4def46cbe665cdf5e1fc8b1ccb1129d732cf09295d0f7a63ae34e2f`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P026)
