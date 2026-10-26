# GX-TXT DEV111-P021 — Native CAD editing inside the 3D viewport

## Italiano

La P021 porta l'editing Sketch **direttamente nel viewport Native3D esistente**: lo Sketch non richiede una seconda vista CAD separata. Gli strumenti CAD condivisi operano sul piano di lavoro selezionato, mantenendo geometria e cronologia nel sistema scientifico originario.

### Funzionalità principali
- **Un solo viewport 3D:** visualizzazione della scena, dei solidi e del Navigation Cube insieme alla geometria Sketch e ai relativi strumenti di editing.
- **Overlay planare integrato:** disegno di griglia, profili, curve, controlli, selezioni, quote, vincoli e proposte mediante presentazione trasparente, mantenendo la scena tridimensionale sottostante.
- **Coordinate e piani orientati:** mappatura fra coordinate del mouse, piano Sketch e spazio 3D, con aggiornamento della proiezione durante i movimenti della camera.
- **Strumenti CAD condivisi:** creazione, modifica, snapping, Finish/Cancel, Undo/Redo, salvataggio e riapertura dello stesso Document/Sketch tramite le API comuni.
- **Navigazione e rappresentazione:** orbit, pan, zoom, interazione con Navigation Cube e mantenimento del contesto 3D mentre si lavora sulla geometria.
- **Viewer e Workbench:** aggiornamento dei componenti Native3D, Scientific 3D Workbench, Test CAD 1/2, anteprima e percorso di inizializzazione grafica Hardware/Software/Auto.
- **Architettura:** Native2D continua a gestire geometria e vincoli; CORE History mantiene la cronologia; Native3D gestisce camera, scena e rendering.

**Sequenza:** applicare dopo DEV111-P020. L'archivio contiene le istruzioni e il gestore di applicazione/ripristino in `patch_notes/DEV111-P021/`.

[File e manifest della P021](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P021)

## English

DEV111-P021 moves Sketch editing **into the existing Native3D viewport**, instead of displaying a separate CAD view. The shared CAD tools operate on the selected 3D workplane while the established scientific geometry and History remain authoritative.

### Main features
- **One integrated 3D viewport:** scene, solids and Navigation Cube displayed together with Sketch geometry and edit controls.
- **Projected CAD overlay:** transparent retained presentation of grid, curves, controls, selection, dimensions, constraints and pending operations above the Native3D scene.
- **Oriented planes and input mapping:** mapping between pointer coordinates, Sketch workplanes and world coordinates as the camera moves.
- **Shared CAD workflows:** construction, snapping, editing, Finish/Cancel, Undo/Redo, save and reopen through the existing Document and public CAD APIs.
- **Native 3D navigation:** orbit/pan/zoom and Navigation Cube interaction without leaving the drawing context.
- **Integrated consumers:** Scientific 3D Workbench, Native3D components, Test CAD 1/2, Builder Preview and Hardware/Software/Auto rendering initialization.
- **Separated responsibilities:** Native2D owns exact geometry/constraints; CORE History owns edit history; Native3D owns the scene, camera and rendering.

**Order:** apply after DEV111-P020. Refer to `patch_notes/DEV111-P021/` for the included application and rollback helpers.

[P021 files and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P021)
