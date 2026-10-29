# GX-TXT DEV111-P028 — Scientific Libraries, Dataset Groups and Script Projects

## Italiano

**DEV111-P028 — Librerie scientifiche, gruppi Dataset e progetti Script**

Estende GX-TXT con librerie scientifiche tipizzate, adattatori per sorgenti esterne, gruppi Dataset, importazione Rigol, progetti Python/Octave multifile e controlli Runtime condivisi.

### Funzionalità
- Introduce librerie scientifiche tipizzate e relazioni fra risorse, consultazione ricercabile delle sorgenti, Library Browser e inserimento manuale guidato da schemi con allegati PDF/immagini/disegni originali.
- Comprende adattatori indipendenti per PubChem, LCSC e Mouser, mantenendo separate consultazione delle sorgenti, popolamento delle librerie e acquisizione esplicita in Dataset.
- Introduce Dataset Groups persistenti con identità dei membri, operazioni atomiche di ciclo di vita e Namespace, import/export portabile dei gruppi.
- Aggiunge l'importazione nativa/HDF5 di acquisizioni Rigol estese, con Dataset float64 indipendenti per canale e una risorsa gestita condivisa.
- Fornisce Preview delle forme d'onda nativo a memoria limitata e un componente Preview per oscilloscopio sviluppato con il Builder e distribuibile separatamente.
- Introduce progetti Script Python/Octave multifile, buffer indipendenti negli editor, Save All, snapshot immutabili dei job, debugger consapevole dei file e parametri Runner tipizzati.
- Aggiorna configurazione Runtime e controllo delle dipendenze degli interpreti, riutilizzando le autorità esistenti per Dataset, Script Job e Publication.
- La distribuzione P028 originale è conservata accanto alla P028-r2, revisione alternativa basata anch'essa sulla P027.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P027` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P028.zip` (SHA-256: `6a03129e5daf729f33ca62b362da86d7ee83b1a3e594b6d87f0cf60b41b135a2`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P028)

## English

**DEV111-P028 — Scientific Libraries, Dataset Groups and Script Projects**

Extends GX-TXT with typed Scientific Libraries, source adapters, first-class Dataset Groups, Rigol waveform import, Python/Octave multifile projects and shared runtime controls.

### Features
- Adds generic typed Scientific Libraries and relationship management, searchable source consultation, Library Browser, and manual schema-driven entry with original PDF/image/drawing attachments.
- Provides separately packaged source adapters for PubChem, LCSC and Mouser, preserving source identity and explicit consultation, Library population and Dataset Acquisition steps.
- Introduces persistent Dataset Groups with stable member identity, atomic lifecycle and Namespace operations, and portable Group import/export.
- Adds native/HDF5 import of large Rigol recordings with independent float64 channel Datasets grouped under one shared managed Resource.
- Provides bounded native waveform Preview and a separately distributable Builder-authored oscilloscope Preview.
- Introduces multifile Python and Octave Script Projects with independent editor buffers, Save All, immutable execution snapshots, source-aware debugging and typed runner parameters.
- Updates Runtime configuration controls and interpreter dependency auditing while retaining the established Dataset, Script Job and publication owners.
- This original P028 distribution is preserved alongside P028-r2, an alternative revision whose base is also P027.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P027`, according to the bundled README.

Original archive: `DEV111-P028.zip` (SHA-256: `6a03129e5daf729f33ca62b362da86d7ee83b1a3e594b6d87f0cf60b41b135a2`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P028)
