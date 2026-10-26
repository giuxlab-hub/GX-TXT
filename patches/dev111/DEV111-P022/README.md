# GX-TXT DEV111-P022 — Native3D rendering, Sketch lifecycle and GUI responsiveness

## Italiano

La P022 estende l'integrazione CAD/Native3D della P021 intervenendo sull'avvio del renderer, sul trasporto delle immagini, sugli eventi della camera e sulla gestione degli Sketch salvati.

### Funzionalità principali
- **Avvio grafico Hardware:** gestione mirata dell'inizializzazione del processo renderer con driver NVIDIA 390 e propagazione dei dati diagnostici relativi al dispositivo grafico.
- **Eventi della camera:** accodamento e raggruppamento ordinato degli input di navigazione, senza perdere le operazioni ricevute dalle anteprime Native3D.
- **Trasferimento delle immagini:** riduzione del costo dei frame intermedi PNG nei percorsi GUI condivisi, mantenendo separata l'esportazione scientifica.
- **Proiezione CAD più efficiente:** elaborazione raggruppata delle coordinate native e riutilizzo delle rappresentazioni geometriche già disponibili.
- **Viste temporaneamente non proiettabili:** gestione degli orientamenti limite della camera, evitando che un'interazione non mappabile alteri lo stato dello Sketch.
- **Sketch dopo la chiusura dell'editor:** mantenimento della rappresentazione della geometria salvata nel viewport 3D, con successiva riapertura dello stesso Document e della cronologia.
- **Ciclo di vita del Workbench:** transizioni esplicite fra editing, Finish/Cancel, Close e riapertura; aggiornamenti della gestione Native3D e degli esempi CAD.

**Sequenza:** applicare dopo DEV111-P021. Procedura e ripristino in `patch_notes/DEV111-P022/`.

[File e manifest della P022](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P022)

## English

DEV111-P022 extends the P021 CAD/Native3D integration with changes to renderer startup, image transport, camera input and persistent Sketch display.

### Main features
- **Hardware renderer startup:** targeted handling of NVIDIA 390 renderer-process initialization and device/error diagnostics.
- **Camera input batching:** ordered processing of queued navigation events in Native3D Preview and Viewer paths.
- **Intermediate frame transport:** lower-cost PNG transfer in shared GUI rendering without changing scientific export encoding.
- **CAD projection updates:** batched native coordinate transforms and reuse of previously prepared geometric representations.
- **Unmappable camera orientations:** guarded CAD pointer dispatch while preserving committed and in-progress Sketch data.
- **Saved Sketch visibility:** completed geometry remains displayed after the editor closes; reopening restores the associated Document and History.
- **Workbench lifecycle:** explicit transitions for edit/Finish/Cancel/Close/reopen, including the updated Scientific 3D Workbench and CAD consumers.

**Order:** apply after DEV111-P021. See `patch_notes/DEV111-P022/` for application and rollback.

[P022 files and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P022)
