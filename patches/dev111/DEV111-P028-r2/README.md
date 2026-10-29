# GX-TXT DEV111-P028-r2 — Scientific Libraries, Group Workflows and Script Projects — Revision 2

## Italiano

**DEV111-P028-r2 — Librerie scientifiche, gruppi e progetti Script — revisione 2**

Revisione della P028 con Scientific Library Workspace integrato, consultazione delle sorgenti filtrabile e riutilizzabile, acquisizione a fasi, gruppi Dataset, forme d'onda Rigol e progetti Script multifile.

### Funzionalità
- Integra Records, Sources e Manual Entry come pagine coordinate dell'attuale Scientific Libraries Workspace, con dettagli tecnici, immagini/PDF incorporati e ricevute delle operazioni.
- Espone un gruppo di tre pagine riutilizzabile dai Viewer, con filtri dichiarativi su tipi di libreria, tipi di record, Library ID, Provider ID e Source ID, applicati prima del conteggio e della paginazione.
- Separa la consultazione delle sorgenti, possibile anche senza Session, dalla successiva Acquisition/Publication selezionata e confermata verso Session e Namespace di destinazione.
- Mantiene i moduli PubChem, LCSC e Mouser indipendenti; i record tecnici inseriti manualmente conservano valori, unità, condizioni, provenienza e allegati originali in revisioni immutabili.
- Comprende Dataset Groups e acquisizioni Rigol come quattro Dataset di canale float64 a piena risoluzione, pubblicazione nativa/HDF5 e Preview a memoria limitata.
- Include progetti Script Python/Octave multifile, schede sorgente condivise, Save All atomico, debugger consapevole dei file, parametri Runner tipizzati per invocazione e snapshot immutabili dei Job.
- Aggiorna presentazione del C++ Viewer Workspace, configurazione Runtime e Catalogo API nativo, con 2.627 dichiarazioni indicizzate nei sorgenti.
- P028-r2 è una patch cumulativa alternativa da DEV111-P027 esatta, non una patch da installare dopo P028. La P028 originale rimane disponibile separatamente.

### Distribuzione
Framework: `GX-TXT 0.9.8.10-dev-111`. Prerequisito: `DEV111-P027` secondo il README dell'archivio.

Archivio ufficiale: `DEV111-P028-r2.zip` (SHA-256: `21e17dbab2173824ba90c04b1558cc83b256d80b3a0f8d77b09940ebc8b5f750`).

La patch contiene i file incrementali e le istruzioni di applicazione/ripristino in `patch_notes/`.

[Codice, archivio e manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P028-r2)

## English

**DEV111-P028-r2 — Scientific Libraries, Group Workflows and Script Projects — Revision 2**

Revised P028 delivery integrating the Scientific Library Workspace interface, scoped reusable records/sources/manual entry, staged acquisition, Dataset Groups, Rigol waveforms and multifile Script Projects.

### Features
- Integrates Records, Sources and Manual Entry as coordinated pages of the existing Scientific Libraries Workspace, including embedded technical details, source images/PDFs and operation receipts.
- Exposes a reusable three-page Viewer component with declarative filters for library types, record types, library IDs, provider IDs and source IDs, applied before count and paging.
- Separates source consultation without a Session from later, explicitly selected and reviewed Acquisition/Publication into a destination Session and Namespace.
- Retains independent PubChem, LCSC and Mouser modules; manual technical records can preserve numeric values, units, conditions, provenance and original attached files through immutable revisions.
- Provides first-class Dataset Groups and Rigol acquisition as four independent full-resolution float64 channel Datasets, native/HDF5 publication and bounded waveform Preview.
- Includes Python/Octave multifile Script Projects, shared source tabs, atomic Save All, file-aware debugging, per-invocation typed Runner parameters and immutable Script Job snapshots.
- Updates the C++ Viewer Workspace presentation, Runtime configuration and native API Catalog, with 2,627 source-indexed declarations in the delivered catalog.
- P028-r2 is an alternative cumulative patch from exact DEV111-P027, not an overlay to apply after P028. The original P028 release remains separately available.

### Distribution
Framework: `GX-TXT 0.9.8.10-dev-111`. Required predecessor: `DEV111-P027`, according to the bundled README.

Original archive: `DEV111-P028-r2.zip` (SHA-256: `21e17dbab2173824ba90c04b1558cc83b256d80b3a0f8d77b09940ebc8b5f750`).

The patch includes incremental files and its application/rollback instructions under `patch_notes/`.

[Files, archive and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P028-r2)
