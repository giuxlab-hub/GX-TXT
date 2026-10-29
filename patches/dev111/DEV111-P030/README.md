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
- Include Curve Digitizer 2.0.20, fornito senza modifiche dall'autore. L'autore riferisce circa otto ore di test diretti. La qualifica OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST indica esclusivamente che gli agenti, su esplicita richiesta dell'autore, non hanno ripetuto i test né modificato il modulo, per evitare alterazioni accidentali del software già verificato dall'autore.
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
- Includes the author's unchanged Curve Digitizer 2.0.20. The author reports approximately eight hours of direct testing. OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST means only that additional agent retesting or modifications were expressly prohibited to avoid accidental changes to the author-tested module; it does not mean the author left the module untested.
- Markdown rendering supports a documented subset, not all CommonMark features: internal anchors and relative document links remain unsupported. P031–P035 are not part of this release.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P029`, according to the bundled README.

Original archive: `DEV111-P030.zip` (SHA-256: `71929d3999c2ede5b3d0a85b7fbc0de31cc6773a9834fa8cd6d280a2a3390850`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P030)

### Pacchetti moduli / Module packages

Gli archivi dei moduli `analysis.python_script_1.6.2_dev111_p030.zip`, `analysis.octave_script_1.8.2_dev111_p030.zip`, `viewer.development_workspace_1.2.5_dev111_p030.zip`, `viewer.interface_builder_1.2.9_dev111_p030.zip`, `viewer.markdown_documents_1.0.2_dev111_p030.zip`, `preview.markdown_document_1.0.0_dev111_p030.zip`, `viewer.curve_digitizer_2.0.20_publication_classification.zip` sono alternative autonome per un host compatibile; la patch framework include già tutti i moduli elencati; non è prevista una seconda installazione.

The seven companion module archives are alternative standalone packages for a compatible host; the full framework patch already includes all listed modules, so a second installation is not required.

### Qualificazione Curve Digitizer 2.0.20 / Curve Digitizer qualification

**OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST.** L'autore di Curve Digitizer 2.0.20 dichiara di averlo testato personalmente per circa otto ore. Ha espressamente richiesto agli agenti di non ripetere prove funzionali, numeriche, GUI, installazione, regressione, compatibilità o API, per non rischiare modifiche o danni al modulo già verificato. Questa qualifica NON significa che l'autore non abbia eseguito test. Il pacchetto originale è immutato; gli agenti hanno controllato solo identità e checksum del file. La durata dei test è dichiarata dall'autore e non è certificata indipendentemente dagli agenti. SHA-256: acbc81a77ed1625bde3030e871ec88513a28f08b1317780f8e95b3e2b10ff152.

The author reports approximately eight hours of his own testing of Curve Digitizer 2.0.20. He expressly prohibited additional functional, numerical, GUI, installation, regression, compatibility and API tests by agents, to avoid inadvertently damaging or changing software already tested by him. NOT_TESTED_BY_OWNER_REQUEST therefore refers only to the absence of additional AGENT retesting, not to a lack of tests performed by the author. The publication agent verified only the unchanged archive identity and checksum. The author's reported testing duration is not independently certified by the publishing agent.
