# GX-TXT DEV111-P035 — IR Spectroscopy Viewer, Teaching Labs and CORE Cache Bridge 022

## Italiano

**Viewer IR, laboratorio didattico e CORE Cache Bridge 022**

Completa la famiglia IR con Viewer C++ nativo, librerie scientifiche, generatori didattici e CORE Cache Bridge 022.

### Funzionalità

- L'archivio principale P035 modifica il CORE; i moduli esterni rimangono pacchetti gestiti separatamente nel Plugin Manager.
- Include Viewer IR nativo, Analysis spettroscopica, Library IR di riferimento e aggiornamenti Plot/Builder.
- Integra CORE Cache Bridge 022 e il Preview Curve Digitizer 0.1.12 originale, che richiede questa nuova infrastruttura.
- Distribuisce cinque generatori didattici IR autonomi e una Generator Library aggiuntiva, conservando le collezioni già presenti.
- Comprende esercitazioni sulla ricerca in librerie IR e sull'uso di riferimenti NIST/PNNL e RefIMP, con limiti scientifici documentati.
- Ordine di installazione: prima CORE P035, poi verifica dei postimage, quindi i moduli esterni tramite Plugin Manager e la Generator Library tramite il proprio gestore.
- Rollback del CORE solo dopo la rimozione o il ripristino ordinato dei moduli esterni dipendenti.

### Distribuzione

Questa patch richiede esattamente **DEV111-P034**. L'archivio originale `DEV111-P035.zip` ha SHA-256 `8848e8e3f7ada48d7d2b8b34780a398dc83a8829424f64e2dc63c60487b2447d` ed è preservato senza modifiche.

I moduli distribuiti appartengono alla release GX-TXT: **nessuno viene escluso o rimosso**. Sono pubblicati tutti gli ZIP della consegna, inclusi i moduli, gli eventuali generatori e i materiali didattici integrativi. I loro checksum sono disponibili separatamente.

La patch P035 aggiorna il CORE e include, nella stessa distribuzione, moduli esterni destinati al Plugin Manager: applicare il CORE con le istruzioni originali, verificare i postimage, quindi installare i moduli esterni attraverso i rispettivi gestori. Non copiare i loro file direttamente sul CORE e non forzare il Registry.

Per tutte le patch: mantenere il backup, arrestare GX-TXT e i worker prima dell'applicazione, utilizzare gli script originali di controllo/applicazione/rollback contenuti nell'archivio. La semplice estrazione dello ZIP non sostituisce tali procedure. I file Session/RAW e le installazioni esistenti non vengono modificati da questa pubblicazione.

[Codice, pacchetti, manifest e README](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P035)

## English

**IR Spectroscopy Viewer, Teaching Labs and CORE Cache Bridge 022**

Completes the IR spectroscopy family with a native C++ Viewer, scientific libraries, teaching generators and CORE Cache Bridge 022.

### Features

- The primary P035 archive updates CORE; external modules remain separately managed Plugin Manager packages.
- Ships a genuine native IR Viewer, spectroscopy Analysis, IR reference Library and Plot/Builder updates.
- Integrates CORE Cache Bridge 022 alongside the original Curve Digitizer Preview 0.1.12, which requires the new CORE bridge.
- Delivers five normal IR teaching generators plus an additive Generator Library without replacing existing collections.
- Includes IR reference-library exercises using NIST/PNNL and RefIMP material, with documented scientific limitations.
- Install in order: P035 CORE first, verify CORE postimages, then install external companions via Plugin Manager and the teaching Library through its normal owner.
- Before CORE rollback, first remove or revert newer dependent external companions through their supported manager.

### Distribution and installation relationship

The exact required predecessor is **DEV111-P034**. Original `DEV111-P035.zip` SHA-256: `8848e8e3f7ada48d7d2b8b34780a398dc83a8829424f64e2dc63c60487b2447d`. Original package bytes are preserved.

All delivered modules are **part of this GX-TXT release**. None have been removed or omitted. Module ZIPs, teaching generators and relevant supporting packages are attached to the release with exact checksums.

P035 contains a CORE overlay and also separately managed external modules within its GX-TXT distribution. Apply the CORE overlay first, verify CORE postimages, then install the external components using their normal Plugin Manager/Generator Library workflows. Never force raw overlays or Registry ownership.

Back up and stop GX-TXT and its workers before applying any patch. Use the exact guarded apply/check/rollback procedures included in each original archive; plain ZIP extraction does not implement deletion/rollback. No owner's live installation or Session/RAW is changed by GitHub publication.

[Original source, modules and manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev111/patches/dev111/DEV111-P035)

### Delivered archive inventory

| Category | Original archive | SHA-256 |
| --- | --- | --- |
| Framework | `DEV111-P035.zip` | `8848e8e3f7ada48d7d2b8b34780a398dc83a8829424f64e2dc63c60487b2447d` |
| Module | `analysis.spectroscopy.ir_1.2.0_dev111_p035.zip` | `03350045212f36de075d0141084728ee679e1770920d03e68771bfa31b316a80` |
| Module | `library.spectroscopy.ir.reference_1.2.0_dev111_p035.zip` | `3e1701cf9cfd10bfd512ffbe0288cde591281219127633c38084f6d5913ad904` |
| Module | `plot.dataset_4.4.1_dev111_p035.zip` | `ef4434b3d4b367b74f50549691c366ecce117197ff05a9031459afc71050c529` |
| Module | `preview.curve_digitizer_0.1.12_dev111_p032_REQUIRES_CORE_BRIDGE_022.zip` | `57a0ae932bef79c64d597299581f7319ed30548bc0c2a7846bcace34c436c5b2` |
| Module | `viewer.interface_builder_1.2.13_dev111_p035.zip` | `ccbf65948ccc543c10a6ea57662525a5dc1e9963ee979cb7d3308624aacab181` |
| Module | `viewer.ir_spectroscopy_1.0.1.zip` | `a6f3bd729e09c91a9dd2a458f2c5db475f48bedf84a240eb11684cadd45e0e37` |
| Generator | `gxtxt_ir_library_explorer_lab_1.0.0.zip` | `67db684511b8064789bf334748134bc3b0a1e7959f3de77910b36ecb1b4ee778` |
| Generator | `gxtxt_ir_spectral_contracts_lab_1.0.0.zip` | `2d7e57fb2b21a353554e774e33a2aba7ab20b8dfce49d4aacf2767a27f9499f5` |
| Generator | `gxtxt_ir_teaching_labs_1.0.0.zip` | `71338764583a5b644ce19101d7a923f9042bf0eeefb7e2c9adc8e4aceb08ed41` |
| Generator | `gxtxt_ir_viewer_integrated_study_lab_1.0.0.zip` | `b88eefffdd7dc4a345747cd9f4beb254b690018005a240541f9aabe001e5c9a3` |
| Generator | `gxtxt_nist_pnnl_ir_faculty_1.1.0.zip` | `ef1b72fd89e3224c4a0f802a48f46346cb11bd909aef5a344005f65f48287146` |
| Generator | `gxtxt_refimp_full_training_ir_1.1.0.zip` | `7e5ff019daa71919a034bb49bb75881401f927ea5bbbe1c58a046c61a7c977a0` |
| Teaching material | `P035_ir_library_explorer_lab_Author-html.zip` | `c9e40895907c30ef404ddb409a5dedd00219c93ec07d205f7d6783962b86f71a` |
| Teaching material | `gxtxt_ir_library_explorer_lab_1.0.0_DEMO.gxtxt-session.zip` | `bcc66725efee3848cf9145c120721e8067a2e68d88dbad9f868f2777fdfdec20` |
| Teaching material | `P035_ir_spectral_contracts_lab_Author-html.zip` | `2783d6463fe3253413e1404fdd5b1ae21e6f85e080a6def3073330a086766395` |
| Teaching material | `gxtxt_ir_spectral_contracts_lab_1.0.0_DEMO.gxtxt-session.zip` | `4311900bb0951994ea414c779d28ec4476a458af5ad55d2515ea19a65d2e9845` |
| Teaching material | `P035_ir_viewer_integrated_study_lab_Author-html.zip` | `67551db69836472713a31e6cffe587d47f94b1c2865d5695a72c03293203b26b` |
| Teaching material | `gxtxt_ir_viewer_integrated_study_lab_1.0.0_DEMO.gxtxt-session.zip` | `eae3a4befdb454da145a7c957be2651a7a75fd0f810f4145adefcb05313952af` |
| Teaching material | `P035_nist_pnnl_ir_faculty_Author-html.zip` | `5887e8755320df80caf13e112f767b760cec6fac1d0c39324f1bf02120f1ddf0` |
| Teaching material | `gxtxt_nist_pnnl_ir_faculty_1.1.0_DEMO.gxtxt-session.zip` | `f3d63877dd3fa3bdd154b1d587c2712965a9cef6dcaf514c13c809275708fbe5` |
| Teaching material | `P035_refimp_full_training_ir_Author-html.zip` | `352e3cebf7427532ae65b6949528036870e472e9b086b6fdb4de47ff4dffcb24` |
| Teaching material | `gxtxt_refimp_full_training_ir_1.1.0_DEMO.gxtxt-session.zip` | `fb2f30a07e4ff44852277ede531bc3e0b39c6f3e2948b346930caab25b74ba66` |

The original P035 SOURCE_FILES.json is included for transparent path/byte/mode review. The published files are distribution artifacts, not independently recompiled modules. The accompanying public validator verifies archive and declared member identities, not a new full scientific campaign.

*Source commit:* `ce34988db2c7500b60f7235b237b2fdb67e5d434`. *Changed product paths:* 74.

**License:** GNU GPL-3.0-or-later.
