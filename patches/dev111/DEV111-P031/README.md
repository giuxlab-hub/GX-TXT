# GX-TXT DEV111-P031 — UML, Custom Plot Axes, Preview and Markdown Navigation

## Italiano

**UML, assi Plot personalizzati, Preview e navigazione Markdown**

Estende il CORE con documenti UML, strumenti nativi di editing/anteprima, posizioni X nei Plot, controlli Preview e navigazione Markdown.

### Funzionalità

- Introduce documenti UML Class/Sequence condivisi e i moduli C++ UML Editor e UML Preview con controllo delle capacità native.
- Aggiunge coppie posizione/didascalia personalizzate per l'asse X tramite le API pubbliche Plot v2/v3/v4.
- Corregge la persistenza dell'attivazione Preview nella Configuration dell'applicazione e integra l'ottimizzazione Preview r2.
- Completa i link Markdown relativi autorizzati e la navigazione mediante ancore interne.
- Aggiunge Help/About nei menu Acquisition, guida Rigol illustrata e aggiorna sette moduli normali.
- Conserva separatamente l'archivio storico originale Preview Curve Digitizer 0.1.4; il componente aggiornato è 0.1.5.

### Distribuzione

Questa patch richiede esattamente **DEV111-P030**. L'archivio originale `DEV111-P031.zip` ha SHA-256 `40886aa9b4ae88dab262e0a7ee8019b33023ed8ac3a36e4dfc14adfb0a3db827` ed è preservato senza modifiche.

I moduli distribuiti appartengono alla release GX-TXT: **nessuno viene escluso o rimosso**. Sono pubblicati tutti gli ZIP della consegna, inclusi i moduli, gli eventuali generatori e i materiali didattici integrativi. I loro checksum sono disponibili separatamente.

La patch P035 aggiorna il CORE e include, nella stessa distribuzione, moduli esterni destinati al Plugin Manager: applicare il CORE con le istruzioni originali, verificare i postimage, quindi installare i moduli esterni attraverso i rispettivi gestori. Non copiare i loro file direttamente sul CORE e non forzare il Registry.

Per tutte le patch: mantenere il backup, arrestare GX-TXT e i worker prima dell'applicazione, utilizzare gli script originali di controllo/applicazione/rollback contenuti nell'archivio. La semplice estrazione dello ZIP non sostituisce tali procedure. I file Session/RAW e le installazioni esistenti non vengono modificati da questa pubblicazione.

[Codice, pacchetti, manifest e README](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P031)

## English

**UML, Custom Plot Axes, Preview and Markdown Navigation**

Extends CORE with UML documents, native editing/preview modules, custom Plot X positions, Preview configuration and Markdown navigation.

### Features

- Adds shared UML Class/Sequence documents with native C++ UML Editor and UML Preview modules and explicit capability admission.
- Adds custom numeric X position/caption pairs through existing public Plot v2/v3/v4 APIs.
- Corrects framework-wide Preview activation persistence in application Configuration and incorporates the cumulative Preview r2 optimization.
- Completes authorized relative Markdown links and internal anchor navigation.
- Adds Acquisition Help/About, an illustrated Rigol guide and seven ordinary module updates.
- Preserves the original historical Curve Digitizer Preview 0.1.4 package separately; the updated active companion is 0.1.5.

### Distribution and installation relationship

The exact required predecessor is **DEV111-P030**. Original `DEV111-P031.zip` SHA-256: `40886aa9b4ae88dab262e0a7ee8019b33023ed8ac3a36e4dfc14adfb0a3db827`. Original package bytes are preserved.

All delivered modules are **part of this GX-TXT release**. None have been removed or omitted. Module ZIPs, teaching generators and relevant supporting packages are attached to the release with exact checksums.

P035 contains a CORE overlay and also separately managed external modules within its GX-TXT distribution. Apply the CORE overlay first, verify CORE postimages, then install the external components using their normal Plugin Manager/Generator Library workflows. Never force raw overlays or Registry ownership.

Back up and stop GX-TXT and its workers before applying any patch. Use the exact guarded apply/check/rollback procedures included in each original archive; plain ZIP extraction does not implement deletion/rollback. No owner's live installation or Session/RAW is changed by GitHub publication.

[Original source, modules and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P031)

### Delivered archive inventory

| Category | Original archive | SHA-256 |
| --- | --- | --- |
| Framework | `DEV111-P031.zip` | `40886aa9b4ae88dab262e0a7ee8019b33023ed8ac3a36e4dfc14adfb0a3db827` |
| Module | `acq.rigol_csv_2.3.1_dev111_p031.zip` | `b84635242e1d4024dd14647fb57b147427daaac5b770d0c734e3d4d32c4316e2` |
| Module | `acq.text_document_1.2.0_dev111_p031.zip` | `096031fdeacb80455439e59fbd671c5ccdc88b81ac33474ea353e8175f992641` |
| Module | `plot.dataset_4.3.0_dev111_p031.zip` | `641f052e4450ba5c7629b043d17956feab7899bbe37603e88bfe984d5e884ae3` |
| Module | `preview.curve_digitizer_0.1.4.zip` | `c07ae52b27dd81737eb2f95acaf842eb56e6c48f6eccdc6722b41d854335cfac` |
| Module | `preview.curve_digitizer_0.1.5_dev111_p031.zip` | `1e57baf0ee7b3cd6c0368c1b77c79290caed22cd641342390a6ee59ba0a4be07` |
| Module | `preview.uml_document_1.0.0_dev111_p031.zip` | `537999bc4a0c269d0a215b0e5db4568dc440f79fbe5063da27c5971db00d5557` |
| Module | `viewer.interface_builder_1.2.10_dev111_p031.zip` | `6e9e1bc4dffebb58e8f9490a2b64061f3afd4330598a69d6bde6ff979cbae090` |
| Module | `viewer.uml_editor_1.0.0_dev111_p031.zip` | `3a3e8bc7988dea6c4cb0d3efaa6abb153d7d54f6a75e9f859eea4e2ce2bd6061` |

The original P031 SOURCE_FILES.json is included for transparent path/byte/mode review. The published files are distribution artifacts, not independently recompiled modules. The accompanying public validator verifies archive and declared member identities, not a new full scientific campaign.

*Source commit:* `c998fe69626834550164534e22131e9cb8810448`. *Changed product paths:* 180.

**License:** GNU GPL-3.0-or-later.
