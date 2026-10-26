# GX-TXT DEV111-P020 — Managed CAD Sketch, public CAD controls and STDERR Diagnostics

## Italiano

La P020 estende GX-TXT con un componente **Sketch CAD gestito**, collegato ai Document scientifici e alle superfici native 2D/3D, e con un servizio comune di **diagnostica STDERR** consultabile da un Viewer dedicato.

### Funzionalità principali
- **Sketch e piani di lavoro:** creazione, apertura e chiusura degli Sketch nei Workbench 3D, con riferimento a un piano orientato nello spazio, trasformazioni locali/globali e associazione al relativo Document.
- **Geometria CAD e cronologia:** costruzione, selezione e modifica di elementi geometrici, controlli, vincoli, quote, Undo/Redo e persistenza attraverso Native2D e CORE History.
- **Comandi CAD pubblici:** catalogo condiviso di azioni, stato abilitato/selezionato, invocazione unificata e integrazione con menu, toolbar, palette e pannelli dei Viewer. Interfacce `NATIVE2D_API_v1` e componenti GUI condivisi.
- **Due Viewer CAD di riferimento:** `Test CAD 1` e `Test CAD 2`, con layout e modalità di presentazione diverse, realizzati attraverso le API pubbliche Viewer Builder/Development e componenti nativi C++17.
- **STDERR Diagnostics:** raccolta opzionale dello stderr dei processi gestiti, configurazione globale, buffer limitato, file JSONL con rotazione, contatori e consultazione/esportazione asincrona tramite `STDERR_DIAGNOSTICS_API_v1`. Viewer dedicato indipendente dall'attivazione della raccolta.
- **Documentazione e sorgenti:** manuali, definizioni dei Viewer, integrazione native/C++ e strumenti di gestione inclusi nell'archivio.

**Sequenza:** applicare dopo DEV111-P019. Le istruzioni specifiche per applicazione e ripristino sono in `README.md` e `patch_notes/DEV111-P020/` nell'archivio.

[File e manifest della P020](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P020)

## English

DEV111-P020 introduces a **managed CAD Sketch component** connected to scientific Documents and native 2D/3D surfaces, together with a shared **STDERR diagnostics service** and a dedicated Viewer.

### Main features
- **Sketch workplanes:** create, open and close Sketches in 3D Workbenches, with oriented plane frames, local/world coordinate mapping and Document association.
- **CAD editing and History:** exact geometry, selection, defining controls, constraints, dimensions, Undo/Redo and persistent state through Native2D and CORE History.
- **Public shared CAD commands:** common action catalog, enable/checked states and invocation through Viewer menus, toolbars, palettes and Canvas-owned controls; new `NATIVE2D_API_v1` and shared GUI integrations.
- **Two reference CAD Viewers:** `Test CAD 1` and `Test CAD 2` illustrate complementary layouts using public Viewer Builder/Development interfaces and native C++17 components.
- **STDERR Diagnostics:** optional managed-process stderr collection, global configuration, bounded buffers, rotating JSONL logs, counters and asynchronous reading/export via `STDERR_DIAGNOSTICS_API_v1`. Opening the Viewer does not enable collection.
- **Sources and documentation:** Viewer manuals/designs, native C++ integration and maintenance helpers are included.

**Order:** apply after DEV111-P019. See the archive `README.md` and `patch_notes/DEV111-P020/` for application and rollback instructions.

[P020 files and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P020)
