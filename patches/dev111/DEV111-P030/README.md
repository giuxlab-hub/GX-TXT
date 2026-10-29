# GX-TXT DEV111-P030 — Markdown Documents, Contract Visualizers and Dataset Group Producers

## Italiano

**DEV111-P030 — Documenti Markdown, Contract Visualizer e produttori di Dataset Group**

Introduce note Markdown canoniche associate ai sorgenti, editing documentale condiviso, Documents/Preview Markdown C++ tramite Builder, Contract Visualizer e pubblicazione autorizzata dei Dataset Group.

### Funzionalità
- SOURCE_NOTE_API_v1 associa Dataset Markdown canonici alle identità esatte dei sorgenti Python, Octave e C++, con SHA e revisione delle note; sorgente e nota mantengono cicli di vita distinti.
- Aggiunge editor/rendering Markdown condiviso con viste documento/sorgente/metadati, editing nativo, menu e scorciatoie, Save Existing e Publish New autorizzati, immagini PNG gestite, History nominata e Workspace portabile.
- Distribuisce i moduli originali C++ Markdown Documents Viewer 1.0.2 e Markdown Preview 1.0.0 creati con il Builder, preservando i binari compilati autentici senza sostituzioni o ricompilazione.
- Estende la risoluzione di Contract Registry/Visualizer con Open completo e Preview incorporata, identità di proprietà/ereditarietà/raccomandazioni, scelte persistenti e diagnostica in Configuration.
- Introduce DATASET_GROUP_PRODUCER_API_v1: creazione/pubblicazione facoltativamente atomica di gruppi Dataset da produttori autorizzati tramite i servizi CORE Group/Publication esistenti, oltre a raggruppamento host esplicitamente confermato nel menu Dataset.
- Aggiorna Python Script 1.6.2, Octave Script 1.8.2, Development Workspace 1.2.5 e Interface Builder 1.2.9 con note dei sorgenti, binding, funzioni di authoring e manuali.
- Corregge Script Bridge escludendo directory nascoste di staging/rollback dell'Installer dal discovery, senza attenuare le regole di proprietà, versione e duplicati.
- Include Curve Digitizer 2.0.20 consegnato immutato dall'autore, con qualifica OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST: non si dichiarano test funzionali, numerici, GUI, di installazione, regressione, compatibilità o operazioni API sul modulo.
- Il renderer Markdown supporta un sottoinsieme documentato: anchor interne e link relativi rimangono non supportati. P031–P035 non fanno parte della release.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P029` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P030.zip` (SHA-256: `71929d3999c2ede5b3d0a85b7fbc0de31cc6773a9834fa8cd6d280a2a3390850`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P030)

## English

**DEV111-P030 — Markdown Documents, Contract Visualizers and Dataset Group Producers**

Adds canonical Markdown source notes, reusable document editing, Builder-authored C++ Markdown Documents and Preview, Contract Visualizer discovery and authorized Dataset Group publication.

### Features
- SOURCE_NOTE_API_v1 associates canonical Markdown note Datasets with their exact Python, Octave and C++ source-file identities, SHA and note revision; source and note retain distinct lifecycles.
- Adds a shared Markdown editor/renderer with document/source/metadata views, native editing, primary menus and keyboard commands, authorized Save Existing vs Publish New, managed PNG resources, named History and portable Workspace closure.
- Ships the genuine Builder-authored C++ Markdown Documents 1.0.2 Viewer and Markdown Preview 1.0.0 module, retaining original compiled binaries without substituting a rebuild.
- Extends Contract Registry/Visualizer resolution with full Open and embedded Preview, real owner/inheritance/recommendation identities, persisted choices and runtime configuration diagnostics.
- Adds DATASET_GROUP_PRODUCER_API_v1 for producer-bound, optionally atomic Dataset Group creation/publication using the existing CORE Group and Publication owners, plus explicitly reviewed host grouping in the primary Dataset menu.
- Updates Python Script 1.6.2, Octave Script 1.8.2, Development Workspace 1.2.5 and Interface Builder 1.2.9 with source notes, bindings, authoring support and associated manuals.
- Fixes Script Bridge discovery to ignore hidden Installer staging/rollback directories while retaining strict visible-module ownership and duplicate/version checks.
- Carries an unchanged owner-supplied Curve Digitizer 2.0.20 module. Its declared qualification is OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST, with no functional, numerical, GUI, installation, regression, compatibility or API-operation testing claimed.
- Markdown rendering supports a documented subset, not all CommonMark features: internal anchors and relative document links remain unsupported. P031–P035 are not part of this release.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P029`, according to the bundled README.

Original archive: `DEV111-P030.zip` (SHA-256: `71929d3999c2ede5b3d0a85b7fbc0de31cc6773a9834fa8cd6d280a2a3390850`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P030)

### Pacchetti moduli / Module packages

Gli archivi dei moduli `analysis.python_script_1.6.2_dev111_p030.zip`, `analysis.octave_script_1.8.2_dev111_p030.zip`, `viewer.development_workspace_1.2.5_dev111_p030.zip`, `viewer.interface_builder_1.2.9_dev111_p030.zip`, `viewer.markdown_documents_1.0.2_dev111_p030.zip`, `preview.markdown_document_1.0.0_dev111_p030.zip`, `viewer.curve_digitizer_2.0.20_publication_classification.zip` sono alternative autonome per un host compatibile; la patch framework include già tutti i moduli elencati; non è prevista una seconda installazione.

The two module archives are alternative standalone packages for a compatible host; the full framework patch already includes all listed modules, so a second installation is not required.

### Qualificazione Curve Digitizer 2.0.20 / Curve Digitizer qualification

**OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST.** Il modulo Curve Digitizer 2.0.20 è identico all'archivio originale fornito dall'autore. Non sono stati eseguiti test funzionali, numerici, GUI, di installazione, regressione, compatibilità o operazioni API su questo modulo. Il suo SHA-256 è `acbc81a77ed1625bde3030e871ec88513a28f08b1317780f8e95b3e2b10ff152`.

The owner-supplied Curve Digitizer 2.0.20 archive is preserved unchanged. No functional, numerical, GUI, installation, regression, compatibility or API-operation tests are claimed for this module.
