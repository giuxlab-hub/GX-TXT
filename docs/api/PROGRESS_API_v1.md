# GX-TXT Plugin Progress API v1

Versione framework: GX-TXT Pipeline v0.7.8. Licenza: GPL-3.0-or-later.

## Scopo

La Progress API permette a un plugin di comunicare avanzamento e fase di lavoro senza manipolare widget Tcl/Tk e senza usare il canale di logging come progress channel. È opzionale: un plugin che non la usa continua a essere eseguito normalmente.

## Lifecycle

Stati pubblici v1:

- `start` — apertura esplicita del lifecycle;
- `running` — lavoro in corso;
- `completed` — chiusura riuscita esplicita;
- `failed` — chiusura fallita esplicita.

Il parser è intenzionalmente tollerante verso stati futuri come `cancel_requested`/`cancelled`, ma la v0.7.8 non implementa una Cancellation API.

`completed` è semantico: non viene dedotto automaticamente da `current == total`.

## Mode

`determinate` richiede, quando disponibili, `current` e `total` numerici con `total > 0`. La percentuale è calcolata centralmente dal framework.

`indeterminate` è usato quando una misura sensata dell'avanzamento non esiste.

Input numerici non validi, `total <= 0` o current fuori intervallo non devono far fallire il job. La GUI passa a indeterminate oppure limita la percentuale visualizzata a 0..100.

## Campi evento

Ogni evento può contenere:

```text
state       required
mode        determinate | indeterminate
stage       short plugin-owned stage identifier
message     optional human-readable message
current     optional numeric progress value
total       optional numeric total
module_id   framework-injected stable module id
run_id      framework-injected job identity
```

Il framework non conosce a priori gli stage. `loading_data`, `processing`, `rendering`, ecc. appartengono al plugin.

## Transport standard_octave

Il transport v1 è un record strutturato su stdout con prefisso riservato:

```text
@@GXTXT_PROGRESS_V1@@\tstate=running\tmode=determinate\tstage=rows\tmessage=Processing\tcurrent=125\ttotal=500\tmodule_id=my.module\trun_id=...
```

Campi separati da TAB, `key=value`. Nei valori vengono escaped `\\`, TAB, LF e CR.

Il core filtra le righe col prefisso **prima** di inviarle al normale analysis log. Lo stdout scientifico senza prefisso rimane logging/output ordinario. Stderr continua a seguire l'error/log path del checked runner.

Il transport è semplice e deterministico; non usa busy polling e sfrutta lo stesso `fileevent` non-blocking già usato dalla pipeline.

## Environment iniettato dal framework

```text
GXTXT_PROGRESS_ENABLED=1
GXTXT_PROGRESS_MODULE_ID=<module-id>
GXTXT_PROGRESS_RUN_ID=<unique-run-id>
GXTXT_PROGRESS_OPERATION=analysis|rerender
```

Il plugin non deve generare module/session/run identity.

## Runtime declaration

```ini
[progress]
api_version=1
transport=structured_stdout_prefix
prefix=@@GXTXT_PROGRESS_V1@@

[job]
module_id=my.module
run_id=...
operation=analysis
```

## Octave helper API

I file sono in `core/octave/util/`:

```octave
gxtxt_progress_start(stage, message, mode, total)
gxtxt_progress_stage(stage, message, mode, total)
gxtxt_progress_update(current, total, stage, message)
gxtxt_progress_complete(stage, message)
gxtxt_progress_fail(stage, message)
```

### Esempio determinate

```octave
gxtxt_progress_start('loading','Loading data','indeterminate');
...
gxtxt_progress_stage('processing_rows','Processing rows','determinate',rows(data));
for i=1:rows(data)
  % scientific work
  gxtxt_progress_update(i,rows(data),'processing_rows','Processing rows');
endfor
gxtxt_progress_stage('writing_results','Writing results','indeterminate');
...
gxtxt_progress_complete('done','Analysis completed');
```

### Esempio failure

```octave
try
  gxtxt_progress_start('prepare','Preparing','indeterminate');
  % work
  gxtxt_progress_complete('done','Completed');
catch err
  gxtxt_progress_fail('failed','Module failed; see log for details');
  rethrow(err);  % technical detail stays in normal error handling/logging
end_try_catch
```

## Throttling

`gxtxt_progress_update` applica throttling: un update viene emesso quando la percentuale cambia in modo significativo, viene raggiunto il totale, cambia stage o è trascorso circa 0.25 s dall'ultimo update. `start`, `stage`, `completed` e `failed` non vengono soppressi.

Un plugin non deve comunque chiamare progress per ogni singola operazione se non è necessario.

## GUI

La GUI mostra nel pannello Run:

- nome modulo;
- stage;
- message;
- progress bar determinate con current/total/percent;
- progress bar indeterminate.

Non vengono creati popup a ogni update. Il process I/O resta asincrono tramite `fileevent`, quindi gli update non bloccano il Tk event loop.

## Headless

Il protocollo rimane valido senza GUI. Un processo `standard_octave` eseguito dal checked runner emette i record strutturati controllati su stdout; strumenti headless possono filtrarli tramite il prefisso riservato. L'API Tcl `::GX::progressPublish` produce una forma `[progress] ...` quando non esiste una GUI.

## Plugin senza Progress API

Nessuna dichiarazione descriptor è obbligatoria. Se non arrivano eventi, GX-TXT mantiene il comportamento fallback `Running...` e determina successo/fallimento dall'exit status e dall'output contract.

## Rerender

Un rerender può usare la stessa API ma deve descrivere esclusivamente le fasi del rerender, per esempio:

```text
loading_cache -> rendering -> completed
```

Non deve ripetere fasi scientifiche del run originale.

## Progress != logging

Progress: stato sintetico e aggiornabile (`250 / 1000`).

Logging: warning, stdout/stderr scientifico, diagnostica, stack trace, dettagli tecnici.

Non usare `message` per trasferire grandi log.

## In-process Tcl

Codice Tcl interno/framework-facing può pubblicare un dict tramite:

```tcl
::GX::progressPublish [dict create \
    state running mode determinate stage rows message "Processing" \
    current 10 total 100 module_id my.module run_id $runId]
```

Questo metodo non manipola widget direttamente.
