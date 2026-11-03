# GX-TXT DEV112-r2 P004 — Cumulative Update: Canvas and Unified Documents

## Italiano

**Aggiornamento cumulativo: Canvas e Unified Documents**

Riunisce P001–P004 in un unico aggiornamento e migliora il Viewer Unified Documents.

### Funzionalità

- Aggiornamento cumulativo completo da DEV112-r2 originale oppure dalla configurazione esatta successiva alla P003.
- Aggiorna Unified Documents 1.1.0 con pannelli compatti, OCR, tabelle, toolbar e navigazione.
- Integra le migliorie Canvas e mantiene il modello Document, History e Workspace esistente.
- Include il pacchetto Viewer Unified Documents e il Canvas Demonstrator come archivi autonomi.
- Utilizzare lo script apply.py fornito e la procedura di rollback corrispondente alla route originale.

### Installazione

**Prerequisito:** Original DEV112-r2 OR exact post-P003. La P004 si può applicare direttamente alla DEV112-r2 pulita oppure allo stato completo post-P003. Non applicare P001–P003 prima se si sceglie la route diretta dalla base.

La P004 è **cumulativa**: con la route DEV112-r2 originale non occorre eseguire separatamente P001, P002 e P003. Per entrambe le route utilizzare `apply.py` e verificare il target prima di applicare. Per il rollback indicare esplicitamente `--route r2` oppure `--route post-p003`, secondo lo stato iniziale.

```sh
python3 -I -B apply.py FRAMEWORK DEV112-P004.zip --check
python3 -I -B apply.py FRAMEWORK DEV112-P004.zip --apply --owner-authorized --stopped
```

Archivio incrementale originale: `DEV112-P004.zip` (SHA-256 `d0ec6476778f3e4d2fdc781427bbfcb71dcfc1374cae31b5c609d333adf37b44`). Le identità dei 137 file aggiornati e i componenti associati sono nel manifesto della release.

[Archivi e file di progetto](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P004)

## English

**Cumulative Update: Canvas and Unified Documents**

Provides a single cumulative P001–P004 update and improves the Unified Documents Viewer.

### Features

- A cumulative update supported from the original DEV112-r2 base or the exact post-P003 state.
- Updates Unified Documents 1.1.0 with compact panels, OCR, tables, toolbars and navigation.
- Integrates Canvas improvements while retaining existing Document, History and Workspace ownership.
- Includes the Unified Documents Viewer and Canvas Demonstrator as standalone packages.
- Use the supplied apply.py and select the rollback route matching the original installation.

### Installation

**Required predecessor:** Original DEV112-r2 OR exact post-P003. P004 applies either to a clean DEV112-r2 installation or an exact post-P003 state. Do not apply P001–P003 first when using the direct base route.

P004 is **cumulative**: a clean DEV112-r2 host does not require running P001, P002 and P003 separately. Run the supplied `apply.py --check` before any update. Rollback must explicitly select the original `r2` or `post-p003` route.

Original patch archive: `DEV112-P004.zip`, SHA-256 `d0ec6476778f3e4d2fdc781427bbfcb71dcfc1374cae31b5c609d333adf37b44`. The exact identities of the 137 updated files are recorded in the manifest.

[Package files and source manifests](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P004)

### Original package archives

| File | SHA-256 |
| --- | --- |
| `DEV112-P004.zip` | `d0ec6476778f3e4d2fdc781427bbfcb71dcfc1374cae31b5c609d333adf37b44` |
| `viewer.unified_document_extraction_1.1.0.zip` | `e85fb8b6fffdb38c4ad3f83c6714cd2b75cecc7f7c7aa38e5f1f51f218f366e3` |
| `viewer.canvas_demonstrator_1.0.0.zip` | `68f3f821754703ed01cf06bcbd9544e27f90ef79c92929934b15eb13861f848c` |
| `apply.py` | `0551e7ee8de0656d0bbc41414fb6a830de52ae1bbc4fa2d5d526015fca5a7976` |

Release archives are preserved byte-for-byte. Use the included guarded installer and the exact predecessor described above; simple ZIP extraction is not an update operation. Close GX-TXT and its workers before any authorized installation.
