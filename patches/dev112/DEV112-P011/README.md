# GX-TXT DEV112-r2 P011 — Run, Curve Viewer, Curve Fitter and Native3D

## Italiano

La P011 aggiorna GX-TXT 0.9.8.10-dev-112 con miglioramenti ai flussi di esecuzione, ai Viewer scientifici, al fitting e al rendering 3D.

- Run: ammissione attraverso le API pubbliche e gestione dei Job supervisionati.
- Curve Viewer 2D/3D: rappresentazioni tramite Plot v4, pubblicazione esplicita di Graph/Variant, aggiornamento delle sorgenti e Workspace persistenti.
- Curve Fitter: presentazione dei risultati in schede dedicate, History scientifica e gestione distinta delle impostazioni di visualizzazione.
- Native3D: miglioramenti alle aree di margine e alla leggibilità delle etichette, mantenendo geometrie, unità e camera.
- GX-TXT MCP Server 0.2.0: pacchetto Debian opzionale, con compatibilità basata sulle API e sui contratti runtime reali. La sua installazione e configurazione sono indipendenti e non avviano automaticamente il servizio.

Installazione: la P011 richiede esattamente lo stato post-P010; non è cumulativa dalla DEV112-r2 originale. Eseguire il controllo read-only con lo script apply.py e seguire INSTALLAZIONE.md nel pacchetto completo. Conservare la ricevuta esterna per il rollback post-p010.

## English

P011 updates GX-TXT 0.9.8.10-dev-112 with improvements to execution workflows, scientific Viewers, fitting and 3D rendering.

- Run: admission through public APIs and supervised Job management.
- Curve Viewer 2D/3D: Plot v4 representations, explicit Graph/Variant publication, source synchronization and persistent Workspaces.
- Curve Fitter: dedicated results and diagnostics tabs, scientific History and separate presentation settings.
- Native3D: improved figure margins and label legibility while retaining scientific geometry, units and camera.
- GX-TXT MCP Server 0.2.0: optional Debian package with compatibility based on actual public APIs and runtime contracts. Installation and configuration are separate and do not automatically enable the service.

Installation: P011 requires the exact post-P010 state. It is not cumulative from the original DEV112-r2 release. Run the read-only preflight with apply.py and follow INSTALLAZIONE.md in the complete delivery. Retain the external receipt for post-p010 rollback.

### Original distribution files

| File | SHA-256 |
| --- | --- |
| DEV112-P011-overlay.zip | ea02fa968a5b4c75499c620740981d12012b6e77d4024eb744c21e3f54707cff |
| DEV112-P011-delivery.tar.gz | 1ac6b22a397745416316f7e13e9e54336788eff018c336ce26612df038a96696 |
| DEV112-P011-framework-source.tar.gz | b8f083d2f9186ddabc8bc0b5561e191dc8233f18d361c22ef61a94c011ce2475 |
| gxtxt-mcp-server_0.2.0-1_amd64.deb | bb212be4ba000d4a5751800eb07e4304ec3a2bc6d95ab0f48e55d90a2b8b1e7f |
| apply.py | 5c900c145333f9d9b351b66bad8d9ef3242232d8b1f56a9dcae1138031b11e77 |

Source code, manifests and original installation instructions: https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P011
