# GX-TXT DEV112-r2 P008 — Cumulative GUI and Workflow Improvements

## Italiano

**P008 è un aggiornamento cumulativo** della DEV112-r2. Conserva le funzionalità precedenti e migliora l'interfaccia dei Viewer e le procedure operative.

- Plugin Manager: selezione della cartella predefinita tramite Browse, salvataggio esplicito e gestione delle modifiche non salvate.
- Configuration → Modules → Viewers: ricerca interattiva con Reset, riscontri quando non ci sono risultati e protezione della selezione.
- Correzioni di layout, diagnostica, impostazioni e Page Setup attraverso le funzioni esistenti del framework.
- La matrice di accettazione registra **52 requisiti** con relative verifiche.

**Installazione:** sono supportati i framework esatti DEV112-r2 originale, post-P005, post-P006-r5 e post-P007. La P008 può essere applicata direttamente alla DEV112-r2 originale senza eseguire separatamente le patch intermedie. Verificare la distribuzione con SHA-256 e seguire `INSTALLAZIONE.md` nel delivery ZIP. Conservare la ricevuta di installazione per il rollback della route effettiva.

## English

**P008 is a cumulative DEV112-r2 update**, retaining previous functionality and improving Viewer interfaces and common workflows.

- Plugin Manager: Browse for the default package directory, explicit Save, and coherent handling of unsaved changes.
- Configuration → Modules → Viewers: interactive search with Reset, empty-result feedback and guarded selection.
- Corrections in layout, diagnostics, state presentation and Page Setup through existing framework services.
- The acceptance matrix records **52 requirements** and corresponding verification.

**Installation:** exact DEV112-r2 base, post-P005, post-P006-r5 and post-P007 states are supported. P008 can be applied directly to the clean DEV112-r2 release without individually installing prior patches. Verify the SHA-256 checksums and follow `INSTALLAZIONE.md` inside the complete delivery ZIP. Retain the installation receipt for route-specific rollback.

### Original distribution artifacts

| File | SHA-256 |
| --- | --- |
| `DEV112-P008.zip` | `fc931c33cbc9c390b71c5ea3e68bb67de3ce0b4c1252012711d5245bdf7c35ff` |
| `DEV112-P008-delivery.zip` | `64bd9e9b0fb55abc8f87114e72f910470f726a13c2c5be1af1011248a8688552` |
| `DEV112-P008-source.bundle` | `eb2c4dab652c5794f42b2a2bad2176d8c3b36bfcd6ac7d0fec266a60f8f89c19` |
| `apply.py` | `256870b075a75da09053dfff1339be303ef46bada7185eb2c7c0813b4290e988` |

[Source and distribution manifest](https://github.com/giuxlab-hub/GX-TXT/tree/maintenance/dev112/patches/dev112/DEV112-P008)
