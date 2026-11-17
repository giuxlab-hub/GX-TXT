# GX-TXT DEV112-r2 P011-bis — Curve Viewer and Scientific Workflow Corrections

## Italiano

La **P011-bis** è un aggiornamento correttivo da applicare **esclusivamente allo stato esatto della P011 già pubblicata**. Conserva la cronologia precedente e fornisce installer atomico, controlli della sorgente e rollback.

### Correzioni

- **Curve Viewer / Plot Dataset v4:** integrazione Native3D con il motore GX3DE attuale, flussi di anteprima, esportazione, pubblicazione e persistenza, con compatibilità esplicita per i Workspace storici.
- **Curve Viewer:** selezione guidata di Dataset/serie, proprietà e filtri, dialoghi più compatti, scelta dei colori tramite i controlli pubblici UI Field e trascinamento della legenda sul grafico.
- **Curve Fitter:** visualizzazione e diagnostica dei risultati, etichette e unità dei parametri, stili, proporzioni grafiche e corretta descrizione dell'esito del solver.
- **Python, Octave e Script Bridge:** continuità delle sorgenti, preservazione di errori e risultati tipizzati, supervisione dei Job e verifiche della conservazione delle risorse.
- **Documentazione:** manuale illustrato Curve Viewer e ulteriori verifiche scientifiche e GUI.

Il pacchetto completo è stato accettato dai validatori indipendenti GUI, TECH e SCI. Contiene i file originali, le preimmagini P011, il payload corretto, i manifesti e le istruzioni per applicazione, recupero e rollback.

### Installazione

**Prerequisito obbligatorio: DEV112-r2 P011 esatta.** La P011-bis **non** è installabile direttamente sulla DEV112-r2 originale, né sulla P010. Scaricare il **TAR.GZ completo** da questa release e verificarne il checksum SHA-256. Estrarlo in una cartella autonoma e leggere il documento originale `patch/atomic/INSTALL.md`.

Con il framework target fermo e l'autorizzazione all'installazione:

```sh
cd /percorso/del/DEV112-P011-bis-delivery/patch/atomic
python3 apply.py check /percorso/assoluto/del/framework
python3 apply.py apply /percorso/assoluto/del/framework --stopped-target
python3 apply.py status /percorso/assoluto/del/framework
```

Non utilizzare `apply.py` isolato: la procedura richiede il pacchetto esatto completo di manifesti, payload e preimmagini. Conservare le ricevute esterne per recupero e rollback. La pubblicazione GitHub non installa né attiva alcun componente.

**Limite noto:** una didascalia d'asse Native3D può essere poco leggibile quando la telecamera è quasi allineata all'asse. Il problema era già presente nella P011 e **non** viene dichiarato risolto dalla P011-bis.

## English

**P011-bis is a corrective update requiring the exact, accepted DEV112-r2 P011 source state.** It is not a cumulative update for the original DEV112-r2 base or post-P010 installations.

### Changes

- **Curve Viewer / Plot Dataset v4:** modern GX3DE integration, 3D preview/export/publication and Workspace persistence, with explicitly bounded historical Workspace compatibility.
- **Curve Viewer:** guided Dataset and series selection, compact context-aware dialogs, existing public colour controls, filter/style editing and directly draggable plot legends.
- **Curve Fitter:** result and diagnostics presentation, parameter/units labels, preserved style fields, scientific versus display aspect and actual solver status/objective reporting.
- **Python, Octave and Script Bridge:** retained original source identities, typed result/error preservation, supervised Job and resource-retention checks.
- **Documentation:** illustrated Curve Viewer manual plus independently reviewed GUI/scientific regression evidence.

The accepted distribution includes the original complete source, precise P011 preimages, correction payload, atomic installer and exact rollback instructions.

### Installation

**Mandatory prerequisite: exact DEV112-r2 P011.** Download and verify the **complete TAR.GZ** from this release. Read `patch/atomic/INSTALL.md` and stop all processes accessing the target framework. With the installation owner's authorization:

```sh
cd /path/to/DEV112-P011-bis-delivery/patch/atomic
python3 apply.py check /absolute/path/to/framework
python3 apply.py apply /absolute/path/to/framework --stopped-target
python3 apply.py status /absolute/path/to/framework
```

Do not use a detached installer copy: it requires the exact matching manifest, payload and preimages. Retain the receipt, and consult the included recovery/rollback instructions after interruption. Publishing this release does **not** install or activate it on any host.

**Inherited known limitation:** a Native3D axis caption can become unreadable at nearly end-on camera angles. This issue is present in the accepted P011 baseline and is not claimed fixed in P011-bis.

### Original release archives

| File | SHA-256 |
| --- | --- |
| DEV112-P011-bis-curve-viewer-and-audit-corrections.tar.gz | 1c03cdd36905a8795b1088ca4fdc9da4e4a1203c8a62b792f8c3da26e969b8d7 |
| DEV112-P011-bis-framework-source.tar.gz | b1896a068582596de37f7242b73c075d109ec901f455de939c71221095cecd97 |
| DEV112-P011-bis-source-delta.zip | 7f358374e7d5c97dfc18ece509a4923293a4c53326be21a8eefb48b78927543a |
| DEV112-P011-bis-source.diff | 40670d276c842f423799eac414d32f7d8454b06162e6d789d57fa39855206e12 |

[Source metadata and original installation instructions](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P011-bis)
