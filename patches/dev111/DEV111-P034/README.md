# GX-TXT DEV111-P034 — Reusable Comparison Plot and Plot v4 Integration

## Italiano

**Comparison Plot riutilizzabile e integrazione Plot v4**

Aggiunge confronti scientifici Overlay, Top/Bottom, Stacked, Difference e Ratio utilizzando Plot v4, Numeric e riferimenti canonici.

### Funzionalità

- Nuovo Comparison Plot generico sviluppabile nel Builder: Overlay, Top/Bottom, Stacked, Difference e Ratio.
- Riferimenti a Dataset e Library gestite con revisioni, hash, unità e significati fisici preservati.
- Allineamento esplicito senza estrapolazione implicita; divisioni per zero e conversioni non sicure vengono rifiutate.
- Il menu Plot include azioni di presentazione native, con History, Properties, legenda e varianti Graph persistenti.
- Corregge la visibilità nel Plugin Manager dei moduli installati non registrati e la loro adozione gestita.
- Include l'esempio Viewer C++ e gli archivi originali Curve Digitizer 2.0.26 / Preview 0.1.10 senza alterazioni.

### Distribuzione

Questa patch richiede esattamente **DEV111-P033**. L'archivio originale `DEV111-P034.zip` ha SHA-256 `12393a90c14ab511785763edcd114fc3c21587bc3323dfe32043b2b65509a48b` ed è preservato senza modifiche.

I moduli distribuiti appartengono alla release GX-TXT: **nessuno viene escluso o rimosso**. Sono pubblicati tutti gli ZIP della consegna, inclusi i moduli, gli eventuali generatori e i materiali didattici integrativi. I loro checksum sono disponibili separatamente.

La patch P035 aggiorna il CORE e include, nella stessa distribuzione, moduli esterni destinati al Plugin Manager: applicare il CORE con le istruzioni originali, verificare i postimage, quindi installare i moduli esterni attraverso i rispettivi gestori. Non copiare i loro file direttamente sul CORE e non forzare il Registry.

Per tutte le patch: mantenere il backup, arrestare GX-TXT e i worker prima dell'applicazione, utilizzare gli script originali di controllo/applicazione/rollback contenuti nell'archivio. La semplice estrazione dello ZIP non sostituisce tali procedure. I file Session/RAW e le installazioni esistenti non vengono modificati da questa pubblicazione.

[Codice, pacchetti, manifest e README](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P034)

## English

**Reusable Comparison Plot and Plot v4 Integration**

Adds scientific Overlay, Top/Bottom, Stacked, Difference and Ratio workflows through public Plot v4 and Numeric owners.

### Features

- Adds a generic Builder-authorable Comparison Plot: Overlay, Top/Bottom, Stacked, Difference and Ratio.
- Maintains pinned Dataset/managed-Library revisions, hashes, units and physical interpretations.
- Uses explicit alignment with no silent extrapolation; zero denominators and unsafe numeric conversions refuse.
- Adds native Plot presentation commands, persistent History, Properties, legends and Graph variants.
- Fixes Plugin Manager discovery of installed-but-unregistered packages and controlled managed adoption.
- Includes the C++ example Viewer and unchanged original Curve Digitizer 2.0.26 / Preview 0.1.10 packages.

### Distribution and installation relationship

The exact required predecessor is **DEV111-P033**. Original `DEV111-P034.zip` SHA-256: `12393a90c14ab511785763edcd114fc3c21587bc3323dfe32043b2b65509a48b`. Original package bytes are preserved.

All delivered modules are **part of this GX-TXT release**. None have been removed or omitted. Module ZIPs, teaching generators and relevant supporting packages are attached to the release with exact checksums.

P035 contains a CORE overlay and also separately managed external modules within its GX-TXT distribution. Apply the CORE overlay first, verify CORE postimages, then install the external components using their normal Plugin Manager/Generator Library workflows. Never force raw overlays or Registry ownership.

Back up and stop GX-TXT and its workers before applying any patch. Use the exact guarded apply/check/rollback procedures included in each original archive; plain ZIP extraction does not implement deletion/rollback. No owner's live installation or Session/RAW is changed by GitHub publication.

[Original source, modules and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P034)

### Delivered archive inventory

| Category | Original archive | SHA-256 |
| --- | --- | --- |
| Framework | `DEV111-P034.zip` | `12393a90c14ab511785763edcd114fc3c21587bc3323dfe32043b2b65509a48b` |
| Module | `math.numeric_1.64.0_dev111_p034.zip` | `acc943c49e3a4485ea13d2af02e5d8869299b407f96c7b58118c1e1d7e4c3ade` |
| Module | `plot.dataset_4.4.0_dev111_p034.zip` | `4659da9e9e3c8ce6e974207f70c83eadbd425d615f03fc5d8f345509d40a504f` |
| Module | `preview.curve_digitizer_0.1.10_dev111_p032_standalone.zip` | `0c15e4bae34d5b8d9467fb25c075d63886dab08ecd23010d125e7e854d9f4de7` |
| Module | `viewer.comparison_example_1.0.2.zip` | `4cc0878a07dc6a528a6988cfe50be8801fb2993ad0d6cd14c5a90b59badcbb26` |
| Module | `viewer.curve_digitizer_2.0.26_dev111_p032_standalone.zip` | `ded07ad9a85c79f68fa53866edef9a4a186ef06546882940526b56d9894a1198` |
| Module | `viewer.interface_builder_1.2.12_dev111_p034.zip` | `4a1b1596dd9e6e7b46c2692e841a30dd8c72232c15ebcba3ae1b9e3e968d5747` |

The original P034 SOURCE_FILES.json is included for transparent path/byte/mode review. The published files are distribution artifacts, not independently recompiled modules. The accompanying public validator verifies archive and declared member identities, not a new full scientific campaign.

*Source commit:* `7ae361d67c82f7fce44487a76927c36c846b78b1`. *Changed product paths:* 153.

**License:** GNU GPL-3.0-or-later.
