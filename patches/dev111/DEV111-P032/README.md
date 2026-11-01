# GX-TXT DEV111-P032 — Extensible Acquisition Builder and Native Numeric Clients

## Italiano

**Acquisition Builder estensibile e client numerici nativi**

Amplia l'authoring Acquisition con progetti C++ multifile, helper tipizzati, profili di ingresso e generazione di moduli Preview nativi.

### Funzionalità

- Acquisition Builder produce progetti C++ multifile, configurazioni tipizzate, profili di ingresso e contratti dichiarati.
- Introduzione di validazione e test di Project con riconoscimento/import controllato, senza pubblicazione involontaria di dati.
- Mantiene l'autorità CORE sulla pubblicazione Dataset, i buffer e il ciclo di vita del modulo; niente parser RAW paralleli.
- Il generatore Preview numerico utilizza SDK/exporter reali, distinto dalle demo puramente grafiche del Builder.
- Aggiorna acq.generic_csv, Development Workspace, Interface Builder e Script Module Builder.
- L'overlay richiede esattamente la P031; i moduli C++ necessitano del CORE corrispondente e delle capacità concesse.

### Distribuzione

Questa patch richiede esattamente **DEV111-P031**. L'archivio originale `DEV111-P032.zip` ha SHA-256 `96ad229a771a519c8e45026dd70770581942ec2a3531915098d31c7f00d5f31b` ed è preservato senza modifiche.

I moduli distribuiti appartengono alla release GX-TXT: **nessuno viene escluso o rimosso**. Sono pubblicati tutti gli ZIP della consegna, inclusi i moduli, gli eventuali generatori e i materiali didattici integrativi. I loro checksum sono disponibili separatamente.

La patch P035 aggiorna il CORE e include, nella stessa distribuzione, moduli esterni destinati al Plugin Manager: applicare il CORE con le istruzioni originali, verificare i postimage, quindi installare i moduli esterni attraverso i rispettivi gestori. Non copiare i loro file direttamente sul CORE e non forzare il Registry.

Per tutte le patch: mantenere il backup, arrestare GX-TXT e i worker prima dell'applicazione, utilizzare gli script originali di controllo/applicazione/rollback contenuti nell'archivio. La semplice estrazione dello ZIP non sostituisce tali procedure. I file Session/RAW e le installazioni esistenti non vengono modificati da questa pubblicazione.

[Codice, pacchetti, manifest e README](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P032)

## English

**Extensible Acquisition Builder and Native Numeric Clients**

Extends Acquisition authoring with multifile C++ projects, typed helpers, input profiles and genuine native numeric Preview generation.

### Features

- Acquisition Builder creates multifile C++ projects, typed configuration, input profiles and declared contracts.
- Adds Project validation and recognition/import tests that do not silently publish scientific data.
- Retains CORE ownership of Dataset publication, output buffers and module lifecycle, with no parallel RAW parser.
- The numeric Preview generator uses the actual SDK/exporter, distinct from the Builder's visual-only demos.
- Updates acq.generic_csv, Development Workspace, Interface Builder and Script Module Builder.
- Requires the exact P031 predecessor; native clients need matching CORE ownership and explicit grants.

### Distribution and installation relationship

The exact required predecessor is **DEV111-P031**. Original `DEV111-P032.zip` SHA-256: `96ad229a771a519c8e45026dd70770581942ec2a3531915098d31c7f00d5f31b`. Original package bytes are preserved.

All delivered modules are **part of this GX-TXT release**. None have been removed or omitted. Module ZIPs, teaching generators and relevant supporting packages are attached to the release with exact checksums.

P035 contains a CORE overlay and also separately managed external modules within its GX-TXT distribution. Apply the CORE overlay first, verify CORE postimages, then install the external components using their normal Plugin Manager/Generator Library workflows. Never force raw overlays or Registry ownership.

Back up and stop GX-TXT and its workers before applying any patch. Use the exact guarded apply/check/rollback procedures included in each original archive; plain ZIP extraction does not implement deletion/rollback. No owner's live installation or Session/RAW is changed by GitHub publication.

[Original source, modules and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P032)

### Delivered archive inventory

| Category | Original archive | SHA-256 |
| --- | --- | --- |
| Framework | `DEV111-P032.zip` | `96ad229a771a519c8e45026dd70770581942ec2a3531915098d31c7f00d5f31b` |
| Module | `acq.generic_csv_3_dev111_p032.zip` | `8920db1477440d4c2dcd80422a57cd009d0845952008bb281233fb1aa695e681` |
| Module | `tool.script_module_builder_1.4.6_dev111_p032.zip` | `3fc58409e12179fab3b329714ac3b243a01c01a69c7e4e83f912cd83151fab76` |
| Module | `viewer.development_workspace_1.2.6_dev111_p032.zip` | `700925307e847263b7152e0f09cc4c40ff730d5261e89531ab33bea421690d71` |
| Module | `viewer.interface_builder_1.2.11_dev111_p032.zip` | `42830337d482de31402fb00f493655c1bfbc2663a708a273daa6e76bbbbd8b58` |

The original P032 SOURCE_FILES.json is included for transparent path/byte/mode review. The published files are distribution artifacts, not independently recompiled modules. The accompanying public validator verifies archive and declared member identities, not a new full scientific campaign.

*Source commit:* `fc672ead2755c316025711b9915fdcd6beef4909`. *Changed product paths:* 90.

**License:** GNU GPL-3.0-or-later.
