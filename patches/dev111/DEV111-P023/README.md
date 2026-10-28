# GX-TXT DEV111-P023 — Native 3D Sketch Residency and Document Cache

## Italiano

**DEV111-P023 — Sketch 3D residenti e cache dei Document**

La patch ufficiale P023 integra gli Sketch residenti nella scena Native3D e introduce un percorso più rapido per elencare e aprire i Document.

### Funzionalità
- Mantiene le curve degli Sketch come oggetti residenti nella scena Native3D, insieme a solidi e mesh tridimensionali.
- Gestisce profondità e occlusione native per Sketch su più piani orientati, con selezione diretta per riaprire il Document scientifico di origine.
- Conserva geometria Native2D, vincoli, controlli di editing, CORE History e Document persistente come modello scientifico autorevole.
- Introduce cache limitate dei Document, descrittori quick-open eliminabili e inserimento raggruppato degli Sketch salvati nella scena 3D.
- Integra Scientific 3D Workbench, trasporto pubblico Tcl/C++, identità delle sorgenti e riapertura degli Sketch.
- Utilizza l'identità ufficiale DEV111-P023, distinta dal precedente archivio storico DEV111-P023-EXP01.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P022` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P023.zip` (SHA-256: `10e198b25f392362a82bf61b12978138f9708e6f5ea529377dfd7dff24e85407`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P023)

## English

**DEV111-P023 — Native 3D Sketch Residency and Document Cache**

The official P023 patch brings native resident Sketch geometry and a faster Document listing and opening path into the existing Native3D architecture.

### Features
- Retains derived Sketch curves as native scene actors in the existing 3D viewport, together with solid objects and meshes.
- Provides native depth and occlusion for Sketches on multiple oriented workplanes, with direct picking to reopen the originating scientific Document.
- Keeps exact Native2D geometry, constraints, editing controls, CORE History and persistent Document ownership as the authoritative scientific model.
- Adds bounded verified-byte and parsed-Document caches, disposable quick-open descriptors and batched Native3D admission for previously saved Sketches.
- Integrates the Scientific 3D Workbench, public Tcl/C++ viewer transport, source identity and persisted Sketch reopening.
- Uses the official DEV111-P023 package identity, distinct from the preserved historical DEV111-P023-EXP01 archive.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P022`, according to the bundled README.

Original archive: `DEV111-P023.zip` (SHA-256: `10e198b25f392362a82bf61b12978138f9708e6f5ea529377dfd7dff24e85407`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P023)
