# GX-TXT DEV112-r2 P009 — Scientific Integrations and Public APIs

## Italiano

**P009 è una patch cumulativa** per GX-TXT 0.9.8.10-dev-112. Riunisce l'integrazione delle Guide HTML, le API scientifiche e i miglioramenti ai Viewer esistenti.

- **Viewer e Configuration:** associazioni dei Viewer validate, ricerca dei metadati nei browser e aggiornamento del catalogo API.
- **Plot 2D/3D e PDF:** miglioramenti a colori, legende, griglie, etichette, esportazioni e sfondi Grid/Poster, mantenendo i sistemi di rendering del framework.
- **Guide HTML:** pacchetti di documentazione installabili e consultabili tramite Plugin Manager e Configuration → Modules → Guides.
- **Scientific LaTeX:** build, annullamento, esportazione e gestione delle revisioni attraverso le API pubbliche.
- **Python e GNU Octave:** gestione condivisa di Project, Registry, Jobs, flussi e debugger nativo.
- **GX-TXT MCP Server:** componente Debian **opzionale**, con autenticazione e accesso alle API pubbliche Script Bridge. Installazione e configurazione del servizio sono separate ed esplicite.

**Installazione:** sono ammessi gli stati esatti DEV112-r2 originale, post-P005, post-P006-r5, post-P007 e post-P008. La P009 è cumulativa e può essere applicata direttamente alla release base. Verificare gli SHA-256 e utilizzare `apply.py` con le istruzioni incluse nel pacchetto completo. Conservare la ricevuta di installazione per il rollback della route effettiva.

## English

**P009 is a cumulative patch** for GX-TXT 0.9.8.10-dev-112, adding scientific API integrations, HTML Guides, and enhancements to existing Viewers.

- **Viewers and Configuration:** validated Viewer associations, metadata search in existing browsers and API Catalog integration.
- **2D/3D Plot and PDF:** improvements to colours, legends, grids, labels, exports and Grid/Poster backgrounds through existing rendering owners.
- **HTML Guides:** installable documentation packages managed via Plugin Manager and Configuration → Modules → Guides.
- **Scientific LaTeX:** build, cancel, export and revision workflows through public APIs.
- **Python and GNU Octave:** shared Project, Registry, Job, stream and native debugger operations.
- **GX-TXT MCP Server:** an **optional** Debian component with authentication and Script Bridge API integration, configured and started explicitly.

**Installation:** the exact DEV112-r2 base, post-P005, post-P006-r5, post-P007 and post-P008 baselines are supported. P009 is cumulative and can be applied directly to the original release. Verify SHA-256 and follow the supplied installation script and complete package instructions; retain the receipt for route-specific rollback.

### Original release files

| Artifact | SHA-256 |
| --- | --- |
| `DEV112-P009.zip` | `28c0885963a65453d57b4cc4fa0f665e9a5eeaa78734d142adbf03a29a76abaa` |
| `DEV112-P009-delivery.zip` | `e70ae687bf38a52ec453cb2336604f9bdf91e5efbe5ae59d9a56c33a51ee1405` |
| `gxtxt-mcp-server_0.1.0-1_amd64.deb` | `ca9c9d33606acb4acb264efd31af43d68c7b4b8ba4b8702c5a15b400b15e726c` |
| `DEV112-P009-source.bundle` | `f68614dd50c89c0683c128e9c2386848259cc51944677f6a49671c59bd901f7d` |
| `DEV112-P009-framework-source.tar.gz` | `9736280773048a136e4027987131b219733526370b6a5e849812d96ff6573d37` |
| `apply.py` | `091b4e2248a4b2baca010bcc9b7b370c85c855394126f59502134ceb554256d7` |

[Source manifests and installation instructions](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P009)
