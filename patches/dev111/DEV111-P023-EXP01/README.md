# GX-TXT DEV111-P023-EXP01 — Native resident 3D Sketches and fast Document admission

## Italiano

**DEV111-P023-EXP01** è la variante sperimentale cumulativa della DEV111 dedicata agli Sketch realmente integrati nella scena Native3D. Mantiene il CAD scientifico del progetto e introduce la **residenza nativa delle curve Sketch nella scena 3D**, oltre a un percorso più rapido per riaprire e presentare i Document.

### Funzionalità principali
- **Sketch residenti nella scena 3D:** le curve derivate dai Document CAD sono mantenute come oggetti grafici nativi persistenti nella scena Native3D, senza ricostruire una seconda scena scientifica a ogni movimento della camera.
- **Più piani in un solo viewport:** Sketch su piani differenti condividono la stessa scena e possono essere rappresentati insieme a oggetti e mesh tridimensionali.
- **Profondità e occlusione native:** la geometria Sketch partecipa alla visibilità spaziale rispetto agli altri oggetti 3D.
- **Selezione direttamente dal 3D:** il picking di una curva residente identifica il Document/Sketch corrispondente e apre il relativo editor esatto per la modifica.
- **Editing scientifico invariato:** controlli, griglia, quote, vincoli, snapping, Undo/Redo e geometria restano collegati a Native2D, CORE History e al Document persistente.
- **Memoria e cache:** riutilizzo controllato dei dati Document, cache limitate per contenuto verificato e rappresentazioni già analizzate, con separazione fra dati scientifici persistenti e risorse grafiche eliminabili.
- **Quick open e ammissione in scena:** descrittori/indici derivati per elencare e rappresentare Document senza aprire ogni volta l'intero editor; inserimento raggruppato degli oggetti nella scena.
- **Integrazione esistente:** Workbench 3D, componenti Canvas, Native3D, API Tcl/C++ e Navigation Cube sono riutilizzati; la libreria scientifica Native2D non viene sostituita.

**Identità della release:** `P023-EXP01` (experimental), successiva alla P022 e cumulativa rispetto a P020–P022. L'archivio mantiene il nome e i file originali, comprese le istruzioni del pacchetto sperimentale.

[File e manifest della P023-EXP01](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P023-EXP01)

## English

**DEV111-P023-EXP01** is the cumulative experimental DEV111 variant for Sketches integrated into the existing Native3D scene. It introduces **resident native Sketch geometry** and faster Document listing, opening and scene admission while preserving the established scientific CAD model.

### Main features
- **Resident 3D Sketch geometry:** derived curves remain as native display actors in the existing Native3D scene instead of recreating a second scientific scene for each camera movement.
- **Multiple workplanes, one viewport:** Sketches on different planes coexist with 3D geometry and meshes.
- **Native depth and occlusion:** Sketch geometry participates in 3D visibility relative to other scene objects.
- **Pick-to-edit workflow:** selecting a resident curve resolves its originating Document and opens the exact Sketch editor.
- **Preserved scientific editing:** grid, defining controls, dimensions, constraints, snapping, Undo/Redo and data persistence remain owned by Native2D, CORE History and the Document model.
- **Bounded memory reuse:** verified Document-byte and parsed-registry caches are separate from disposable display resources.
- **Fast Document admission:** derived quick-open descriptors/indexes permit listing and scene population without fully hydrating every editor; native actor admission is batched.
- **Existing host integration:** Scientific 3D Workbench, shared Canvas/GUI components, Tcl/C++ interfaces and Navigation Cube remain part of the same architecture.

**Release identity:** `P023-EXP01` (experimental), following P022 and cumulative with P020–P022. The downloadable ZIP preserves the original experimental package and its own instructions.

[P023-EXP01 files and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P023-EXP01)
