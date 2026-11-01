# GX-TXT DEV111-P033 — Scientific Acquisition, Native Previews and Script Projects

## Italiano

**Acquisition scientifica, Preview native e progetti Script**

Introduce contratti scientifici dimensionali e Preview native, amplia la gestione di progetti Python/Octave e la libreria Script.

### Funzionalità

- Estende la famiglia Acquisition per misure scientifiche, spettri, tracce e frame mediante contratti tipizzati e rappresentazioni dimensionali.
- Distribuisce Preview native per spectrum, trace e frame con provider scientifici separati.
- Aggiunge gestione di progetti e risorse negli editor Python e GNU Octave.
- Integra il Viewer C++ Script Library, con consultazione delle API pubbliche e richiamo dei sorgenti.
- Corregge la presentazione degli strumenti principali del Dataset Browser.
- Mantiene separate le verifiche di contratti scientifici, la validità dei dati e i metadati dei provider.

### Distribuzione

Questa patch richiede esattamente **DEV111-P032**. L'archivio originale `DEV111-P033.zip` ha SHA-256 `b39eff6747900e4b0777d3a06ed5805e8142fda3c1d20edebeb9df2baf812776` ed è preservato senza modifiche.

I moduli distribuiti appartengono alla release GX-TXT: **nessuno viene escluso o rimosso**. Sono pubblicati tutti gli ZIP della consegna, inclusi i moduli, gli eventuali generatori e i materiali didattici integrativi. I loro checksum sono disponibili separatamente.

La patch P035 aggiorna il CORE e include, nella stessa distribuzione, moduli esterni destinati al Plugin Manager: applicare il CORE con le istruzioni originali, verificare i postimage, quindi installare i moduli esterni attraverso i rispettivi gestori. Non copiare i loro file direttamente sul CORE e non forzare il Registry.

Per tutte le patch: mantenere il backup, arrestare GX-TXT e i worker prima dell'applicazione, utilizzare gli script originali di controllo/applicazione/rollback contenuti nell'archivio. La semplice estrazione dello ZIP non sostituisce tali procedure. I file Session/RAW e le installazioni esistenti non vengono modificati da questa pubblicazione.

[Codice, pacchetti, manifest e README](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P033)

## English

**Scientific Acquisition, Native Previews and Script Projects**

Adds dimensional scientific acquisition contracts and native previews while expanding Python/Octave project management and Script Library integration.

### Features

- Extends the Acquisition family with typed scientific measurements, spectra, traces and frames and their dimensional contracts.
- Provides genuine native spectrum, trace and frame Preview modules with distinct scientific providers.
- Adds project and resource management in Python and GNU Octave Script editors.
- Integrates a compiled Script Library Viewer, public API browsing and callable source workflows.
- Corrects the primary Dataset Browser tool presentation.
- Keeps scientific data validity, declared contracts and provider metadata distinct.

### Distribution and installation relationship

The exact required predecessor is **DEV111-P032**. Original `DEV111-P033.zip` SHA-256: `b39eff6747900e4b0777d3a06ed5805e8142fda3c1d20edebeb9df2baf812776`. Original package bytes are preserved.

All delivered modules are **part of this GX-TXT release**. None have been removed or omitted. Module ZIPs, teaching generators and relevant supporting packages are attached to the release with exact checksums.

P035 contains a CORE overlay and also separately managed external modules within its GX-TXT distribution. Apply the CORE overlay first, verify CORE postimages, then install the external components using their normal Plugin Manager/Generator Library workflows. Never force raw overlays or Registry ownership.

Back up and stop GX-TXT and its workers before applying any patch. Use the exact guarded apply/check/rollback procedures included in each original archive; plain ZIP extraction does not implement deletion/rollback. No owner's live installation or Session/RAW is changed by GitHub publication.

[Original source, modules and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P033)

### Delivered archive inventory

| Category | Original archive | SHA-256 |
| --- | --- | --- |
| Framework | `DEV111-P033.zip` | `b39eff6747900e4b0777d3a06ed5805e8142fda3c1d20edebeb9df2baf812776` |
| Module | `acq.scientific_measurement_1.0.2_dev111_p033.zip` | `438fb8c474bfba8eccf88399d716e3906979a5e51a6bf0f7441ed011cc788cb3` |
| Module | `analysis.octave_script_1.8.3_dev111_p033.zip` | `f4d1f98fbd248ec90d4121c7cb5160ff2c38dea3ea0b937ed15e720c347846a7` |
| Module | `analysis.python_script_1.6.3_dev111_p033.zip` | `06d5c5c87bcf4a4dd4b1fa832f0c534b9fb4fda5b1049dff2cf9727bd1ff352d` |
| Module | `contract.scientific_measurement_1.0.0_dev111_p033.zip` | `b6076ea9e6c5fd2e066bf35dca6965d640353b10d5c56a88f4ea47e1d5d2a084` |
| Module | `domain.scientific_spectra_1.1.0_dev111_p033.zip` | `aae6c6670b89e4c6b5c85fc8e816fa556421cf9e3bcaca48e574d02ca6f152e0` |
| Module | `preview.scientific_frame_1.0.1_dev111_p033.zip` | `70c6521ca9f342987845aa2b0d07ece8d9d1c1371a1b1ae7ff60a6406edd26f3` |
| Module | `preview.scientific_spectrum_1.0.1_dev111_p033.zip` | `8e95ebf19645563e120c51cc1af9108f8eba870eba523cbfc176a6a5c4c56b35` |
| Module | `preview.scientific_trace_1.0.1_dev111_p033.zip` | `e7d781ff40c74399fdad28a3a9fb86211b62271b216e97213c2c5a9833ffd781` |
| Module | `tool.script_module_builder_1.4.7_dev111_p033.zip` | `604fe26df647ceffb7384313d36184d43904ef5b61e85b61f18496c2c4f4a4c6` |
| Module | `viewer.script_library_1.0.4_dev111_p033.zip` | `4320405e468bfb5ab93018c22f7e910d03a485da1983fd27b98141090a277320` |

The original P033 SOURCE_FILES.json is included for transparent path/byte/mode review. The published files are distribution artifacts, not independently recompiled modules. The accompanying public validator verifies archive and declared member identities, not a new full scientific campaign.

*Source commit:* `c46767878984f04c4b2fc00fc223f1852a0aad53`. *Changed product paths:* 269.

**License:** GNU GPL-3.0-or-later.
