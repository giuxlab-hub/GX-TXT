# GX-TXT DEV112-r2 P010 — Mathematics Explorer, Plot and Sketch DXF

## Italiano

La **P010** aggiorna GX-TXT 0.9.8.10-dev-112 con nuove funzioni matematiche, miglioramenti dei Plot ed esportazione CAD degli Sketch.

- Mathematics Explorer: variabili nominate, relazioni, piccoli sistemi lineari, rami e intervalli espliciti, famiglie di curve e studio numerico tramite Numeric e Plot v4.
- Plot: precedenza della colorbar, impostazioni di rendering effettivamente applicate, bozze e preset di presentazione.
- Dataset: esportazione generica tramite API pubbliche esistenti.
- Sketch DXF: esportazione esatta dei disegni pubblicati e modulo autonomo installabile con Plugin Manager.
- Esempio scientifico: generatore Mathematics 2D21 e Session dimostrativa con cinque famiglie di dati teorici sintetici.

**Installazione:** la P010 richiede lo **stato esatto DEV112-P009**, e non è cumulativa dalla DEV112-r2 originale. Usare ZIP overlay e script apply.py del pacchetto completo, eseguire prima --check e conservare la ricevuta per il rollback post-p009.

## English

**P010** updates GX-TXT 0.9.8.10-dev-112 with new mathematics workflows, Plot improvements and CAD Sketch export.

- Mathematics Explorer: named variables, relations, small linear systems, explicit branches and gaps, curve families and numerical study via Numeric and Plot v4 public APIs.
- Plot: colourbar precedence, current render settings, presentation drafts and presets.
- Dataset: generic export through established public APIs.
- Sketch DXF: exact published-Sketch export and a separate installable Plugin Manager package.
- Scientific example: a Mathematics 2D21 generator and a sample Session with five synthetic theoretical-data families.

**Installation:** P010 requires the **exact DEV112-P009 state**; it is not cumulative from the original DEV112-r2 base. Use the matching overlay ZIP and apply.py from the full delivery, run --check first and retain the receipt for post-p009 rollback.

### Original distribution files

| File | SHA-256 |
| --- | --- |
| DEV112-P010-overlay.zip | 06c6ed5fbab25d5003f05544a39ec218ed9cb123a2e6140b4fd9dfc292d508f9 |
| DEV112-P010-delivery.tar.gz | 2ea56e67dff8376c09c258ff0b638353472c364ab8370f72f9830651152508ad |
| DEV112-P010-framework-source.tar.gz | 14ad0c867ddbd158af27115ab6c07f55ae4cb8b274abddd54f1630cb708f692c |
| DEV112-P010-source.bundle | cc1005ada6920d92d71b7c171070d0ebad1686cfc81395d6e98a1ddedc99ba6f |
| export.sketch_dxf-1.0.0.zip | 5fc42d89112ce5e10202fec3db6978923f20368014d2ba170fd1ced7bf311692 |
| mathematics_2d21-reference-1.0.0.zip | e66753e48c22db52abc132b072f7f096f99c5a712446f8992fee9d7d41beaba7 |
| DEV112-P010-synthetic-2D21-reference.tar.gz | 2f9800ad281f408371f721696e63bc3bd061fbd953ecd7b00fcab9cd1089c4c3 |
| apply.py | b76b31b8dd6559c69f6b70c4483892e434ee1590da7b81ea2c1197246fb6c80c |

Source, manifests and original installation guide: https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P010
