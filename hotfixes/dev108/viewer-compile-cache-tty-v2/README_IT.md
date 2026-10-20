# GX-TXT dev-108 — hotfix cache di compilazione Viewer / diagnostica TTY (v2)

**Stato:** hotfix sperimentale di manutenzione; test isolati superati, verifica di integrazione GUI Debian ancora da completare.

**Compatibilità esclusiva:** GX-TXT `0.9.8.10-dev-108`, commit originale `6371001a219a4e611ce89c8b396c62294e6b979c`, blob Git del file modificato `5d77772e22ce6eb0befcdc3e32ac783c7d46fbb0`.

**Incompatibilità assoluta:** dev-109 e ogni revisione successiva, versioni differenti e copie della dev-108 già modificate o con una hotfix precedente ancora applicata. Nessun merge nella normale linea `main` o nella dev-109.

## Problema e intervento

Nella dev-108, le azioni ripetute sui Viewer C++ possono richiamare Clang e ricompilare `viewer.so` senza che il progetto sia cambiato. Questa patch prova a riutilizzare la compilazione già riuscita quando coincidono gli hash di sorgente, design, progetto, SDK, policy, compilatore, adapter, toolchain e backend. Modifiche a tali risorse causano la ricompilazione. Build/Export espliciti e compilazioni per il debugger rimangono esclusi dalla cache.

Una compilazione effettiva dovrebbe produrre `COMPILE START` e un messaggio finale `COMPILE OK`, `COMPILE FAILED` oppure `COMPILE ERROR`. La patch tenta di scrivere su `/dev/tty`, senza contaminare `stdout` e `stderr` gestiti dal protocollo del framework. In assenza di terminale di controllo scrive invece nel log limitato `derived/viewer_compilation.log` all'interno del progetto Viewer. Un utilizzo della cache non genera messaggi. Un'istanza Viewer differente può richiedere una compilazione iniziale autonoma.

## Scaricamento

[Archivio originale della hotfix v2](GXTXT_dev108_viewer_compile_cache_TTY_patch_v2.zip)

SHA-256: `4f90e0ed8b510e442a8d80db219e7abbe80ffd59098afa70e69cb4921fd89885`

Lo ZIP contiene `README.md`, `backport.py` e `test_patch.py`. L'unico file del framework modificato è `core/python/gxtxt_viewer_development.py`. Il branch di manutenzione contiene anche il sorgente già corretto per revisione, ma non bisogna eseguire l'installer su quel sorgente modificato.

## Installazione Debian sulla sola dev-108 originale

Chiudere GX-TXT, ripristinare preventivamente l'eventuale patch v1 ed estrarre lo ZIP fuori dalla directory del framework. Dal percorso in cui si trova `backport.py`:

```bash
ROOT="$HOME/gxtxt/gxtxt_pipeline_v09810dev_108"
python3 backport.py --check "$ROOT"
python3 -m unittest -v test_patch
python3 backport.py --apply "$ROOT"
```

I controlli di versione e blob Git sono obbligatori. L'installer crea una copia verificata sotto `<ROOT>/.gxtxt_patch_backups/` e stampa il comando completo per il rollback. Non aggirare i controlli per applicare la patch alla dev-109.

Dopo il riavvio, ripetere più volte un'azione invariata nello stesso Viewer. Osservare le compilazioni effettive e i messaggi; se il terminale non li mostra, consultare il log del progetto interessato.

## Rollback e limiti

Eseguire il comando `ROLLBACK:` visualizzato dall'installer. Se il file è stato modificato nel frattempo, il rollback rifiuta di sovrascriverlo, preservando la copia originale.

Sei test offline con fixture sono passati il 20 ottobre 2026: invalidazione della cache, backup e rollback, messaggi TTY/log e isolamento dei flussi. **Non è stato completato un test di integrazione della GUI Debian con compilazioni Clang reali.** La correzione è temporanea; nella dev-109 il problema sarà risolto in modo indipendente.

**Limite di sicurezza:** i manifest delle compilazioni e i binari sono scrivibili nel progetto. Gli hash identificano le modifiche accidentali, ma non autenticando crittograficamente gli artefatti non impediscono la manipolazione intenzionale. Usare la cache su progetti attendibili: non è una garanzia contro binari nativi malevoli.

Licenza: GNU GPL-3.0-or-later. Il contenuto dello ZIP originale non è stato alterato.