# GX-TXT DEV111-P029 — Python and Octave Script Editor Menus and Source Tabs

## Italiano

**DEV111-P029 — Menu degli editor Python e Octave e schede sorgente**

Unifica i menu degli Script Workspace Python e GNU Octave, introduce la chiusura indipendente delle schede sorgente e la navigazione contestuale, semplificando Save All e la presentazione dei pannelli.

### Funzionalità
- Riorganizza i comandi principali degli editor Python e Octave in una riga File / Edit / Project / View / Run / Help, conservando le operazioni Project esistenti.
- Distingue Save del file attivo da Save All del progetto e rimuove la riga ridondante Project/Save All/Close e il selettore separato dei sorgenti, mantenendo l'albero del progetto.
- Introduce un pulsante di chiusura per ciascuna scheda: chiudendo una scheda inattiva, Save/Discard/Cancel riguarda esattamente quel sorgente, senza cambiare editor attivo in caso di annullamento o rifiuto.
- Aggiunge un menu overflow contestuale per le schede, identità complete dei sorgenti, navigazione Ctrl+Tab e inversa, Ctrl+W per chiudere la scheda attiva e Ctrl+Shift+S per Save All.
- Rende accessibili i menu principali tramite F10, Alt, frecce e Spazio; View Focus source/restore panes agisce sul vero Source Surface.
- Chiudendo l'ultima scheda si apre una nuova bozza non salvata, conservando Registry, revisione/CAS, Script Job, Runner e debugger.
- Aggiorna i moduli Python Script alla 1.6.1 e GNU Octave Script alla 1.8.1, con manuali e screenshot. Nessun componente scientifico nativo viene ricompilato.
- Sono disponibili anche due ZIP dei moduli per host compatibili: la patch completa integra già entrambi i moduli e non richiede di reinstallarli separatamente.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P028-r2` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P029.zip` (SHA-256: `d123201f6bdbea1b6002eb2379eec6905d19cb9a2950faeb48251ac124e83230`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P029)

## English

**DEV111-P029 — Python and Octave Script Editor Menus and Source Tabs**

Unifies Python and GNU Octave Script Workspace menus, introduces independent closable source tabs and contextual overflow navigation, and simplifies Save All and source-pane presentation.

### Features
- Reorganizes the primary commands of the Python and Octave editors into one File / Edit / Project / View / Run / Help menu row, retaining the existing Project actions.
- Distinguishes active-file Save from project-wide Save All and removes the redundant Project/Save All/Close toolbar row and separate source-reference chooser while keeping the project tree.
- Adds a dedicated close control for each source tab: closing an inactive tab uses Save/Discard/Cancel on that exact source without changing the active editor when the operation is cancelled or refused.
- Provides contextual tab overflow with full qualified source identities, Ctrl+Tab and reverse navigation, Ctrl+W to close the active tab, and Ctrl+Shift+S for project-wide Save All.
- Adds keyboard operation of the themed main menus with F10, Alt, arrows and Space; View Focus source/restore panes operates on the actual Source Surface.
- Closing the final source tab opens a new unsaved draft, preserving Registry, revision/CAS, Script Job, Runner and debugger ownership.
- Updates the Python Script module to 1.6.1 and GNU Octave Script to 1.8.1, with corresponding manuals and screenshots. No native scientific component was rebuilt.
- Two alternative standalone module ZIPs are included for compatible hosts; the complete framework patch already bundles both module updates.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P028-r2`, according to the bundled README.

Original archive: `DEV111-P029.zip` (SHA-256: `d123201f6bdbea1b6002eb2379eec6905d19cb9a2950faeb48251ac124e83230`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P029)

### Pacchetti moduli / Module packages

Gli archivi dei moduli `analysis.python_script_1.6.1_dev111_p029.zip`, `analysis.octave_script_1.8.1_dev111_p029.zip` sono alternative autonome per un host compatibile; la patch framework integra già i due moduli, quindi non serve installarli una seconda volta.

The two module archives are alternative standalone packages for a compatible host; the full framework patch already includes both modules, so a second installation is not required.
