# GX-TXT Pipeline v0.7.8 — guida e note di migrazione di `curvefit.family_global`

> **Documento storico v0.7.8.** Il contenuto originale è conservato come nota
> di migrazione, non descrive l'implementazione attuale. Per il modulo 9 leggere
> [README.md](README.md). Gli attuali proprietari sono
> `runtime/curvefit_family_source.m` → CORE Table Stream per gli ingressi canonici,
> `NUMERIC_API_v1` per solver e stime, `STATISTICAL_RESULT_SEMANTICS_API_v1` per
> interpretazione, `runtime/curvefit_family_publish.m` → CORE Publication e
> `runtime/curvefit_family_render_public.m` → Plot Dataset per i grafici.
> Le funzioni locali del vecchio elenco, incluso `read_named_csv3`, sono storiche:
> non devono essere reintrodotte come autorità parallele. Gli ID scientifici,
> i file pubblici e la leggibilità delle cache storiche restano preservati.

## 1. File principale da modificare

Per cambiare **il comportamento del fitting**, il file corretto è:

```text
plugins/modules/curvefit.family_global/runtime/curvefit_family_global_main.m
```

È il file che contiene l'implementazione reale del modulo.

**Non modificare normalmente**:

```text
plugins/modules/curvefit.family_global/runtime/curvefit_family_global.m
```

Quel file è soltanto il launcher CLI: prepara i path del framework e chiama `curvefit_family_global_main(argv())`.

---

## 2. Cosa contiene `curvefit_family_global_main.m`

Il file è diviso logicamente in queste parti.

### A. Ingresso e configurazione

All'inizio della funzione principale:

```octave
function curvefit_family_global_main(args)
```

vengono letti:

- `runtime.ini` passato con `--config`;
- dataset canonico;
- binding `x`, `family`, `y`;
- model plugin selezionato;
- parametri iniziali e limiti;
- solver;
- `max_iter`;
- `tolerance`.

Questa parte va lasciata generica. Non inserire nomi di colonne come `Va`, `Vg`, `Ia` o riferimenti alla 6BX7 direttamente nel modulo.

---

### B. Funzione obiettivo e solver

Il cuore numerico attuale è:

```octave
resfun = @(th) model_fun(th,x,family) - y;
```

Il modulo prova, secondo configurazione:

```text
auto
lsqnonlin
fminsearch
```

`lsqnonlin` è preferito quando il package Octave `optim` è disponibile.

Il fallback `fminsearch` usa:

```octave
fit_fminsearch(...)
bounded_sse(...)
```

Se devi modificare:

- funzione costo;
- pesatura dei residui;
- gestione degli outlier;
- normalizzazione;
- scelta solver;
- criteri di convergenza;

questa è la zona da modificare.

---

### C. Metriche del fit

Dopo il solver vengono calcolati:

```octave
pred
resid
rmse
mae
r2
```

Attualmente:

```octave
pred = model_fun(theta,x,family);
resid = pred-y;
rmse = sqrt(mean(resid.^2));
mae = mean(abs(resid));
```

Se vengono aggiunte altre metriche, ricordarsi di aggiornare anche gli output persistenti.

---

### D. Output obbligatori

Il modulo deve continuare a produrre almeno:

```text
fit_parameters.csv
fit_summary.txt
fit_predictions.csv
render_cache.mat
```

Sono dichiarati nel descriptor `module.ini` e fanno parte dell'output contract del framework.

Le funzioni coinvolte sono:

```octave
write_parameters(...)
write_predictions(...)
write_summary(...)
```

Non rinominare o rimuovere questi file senza modificare contemporaneamente il descriptor del modulo.

---

### E. Grafici

La selezione dei grafici è gestita da:

```octave
render_family(...)
```

I due Graph Provider ID attuali sono:

```text
curvefit.family.overlay
curvefit.family.residuals
```

Le funzioni sono:

```octave
render_overlay(...)
render_residuals(...)
```

I file PNG attuali sono:

```text
01_curve_family_fit.png
02_curve_family_residuals.png
```

Per legenda, DPI, font, assi e stile usare sempre le funzioni comuni del framework:

```octave
gxtxt_setup_graphics()
gxtxt_plot_config()
gxtxt_plot_new_figure(...)
gxtxt_plot_apply_axes(...)
gxtxt_plot_legend(...)
gxtxt_print_png_atomic(...)
```

Non implementare nel modulo una seconda gestione autonoma di legenda, font, DPI o export.

---

## 3. Quando va modificato anche `module.ini`

Il descriptor è:

```text
plugins/modules/curvefit.family_global/module.ini
```

Va modificato **solo se cambia l'interfaccia pubblica del modulo**, per esempio:

- nuovo parametro configurabile;
- nuovo solver visibile nella GUI;
- nuovo grafico;
- nuovo output dichiarato;
- nuovo binding richiesto;
- nuovo campo di configurazione di un grafico.

Esempio: se si aggiunge un parametro configurabile `weighting`, servono sia il codice Octave sia una voce nel descriptor:

```ini
[config]
fields=dataset_id;model_id;solver;max_iter;tolerance;weighting

[config.weighting]
type=choice
label=Residual weighting
default=none
values=none;relative;custom
required=1
```

Poi nel codice si legge con:

```octave
weighting = ini_get(cfg,'config.weighting','none');
```

---

## 4. Quando NON va modificato il curve fitting

Se devi cambiare **l'equazione matematica del modello**, non modificare `curvefit_family_global_main.m`.

Il fitter è generico: chiama il model plugin tramite:

```octave
model_fun(theta,x,family)
```

Per il modello Koren attuale i file sono:

```text
plugins/models/triode.koren_v1/model.ini
plugins/models/triode.koren_v1/runtime/triode_koren_v1.m
```

Quindi:

- modifica dell'algoritmo di fitting -> `curvefit_family_global_main.m`;
- modifica dell'equazione Koren -> `triode_koren_v1.m`;
- modifica di parametri iniziali/bounds del modello -> `plugins/models/triode.koren_v1/model.ini`;
- modifica dei controlli GUI/API del fitter -> `plugins/modules/curvefit.family_global/module.ini` + codice Octave corrispondente.

Questa separazione va mantenuta.

---

## 5. Contratto minimo da non rompere

Il modulo deve continuare a:

1. essere identificato come `curvefit.family_global`;
2. usare il runner `standard_octave`;
3. ricevere il runtime INI tramite `--config`;
4. usare il dataset e i binding forniti dal framework;
5. caricare il model plugin selezionato invece di hardcodare un modello;
6. rispettare i bounds del model plugin;
7. produrre gli output dichiarati;
8. salvare `render_cache.mat` per il rerender senza rifare il fit;
9. usare il Graph Provider API per i grafici;
10. usare il graphics framework comune per legenda/DPI/font/export.

---

## 6. Regole importanti per chi lo modifica

### Non hardcodare il caso 6BX7

Sono vietate dipendenze come:

```octave
x = Va;
family = Vg;
y = Ia;
```

Il modulo deve continuare a lavorare sui ruoli generici:

```text
x
family
y
```

### Non incorporare il modello matematico nel fitter

Il fitter deve chiamare:

```octave
model_fun(theta,x,family)
```

Non deve contenere direttamente la formula Koren o di altri dispositivi.

### Non cambiare i path del framework

Il launcher e il descriptor gestiscono la posizione del modulo. Evitare riferimenti assoluti al filesystem.

### UTF-8 e GPL-3.0-or-later

Mantenere:

```text
UTF-8
SPDX-License-Identifier: GPL-3.0-or-later
```

---

## 7. Procedura pratica consigliata

1. Fare una copia della v0.7.7 funzionante.
2. Modificare prima solo:

   ```text
   curvefit_family_global_main.m
   ```

3. Se viene aggiunta una nuova opzione pubblica, aggiornare anche `module.ini`.
4. Non modificare il launcher `curvefit_family_global.m`.
5. Avviare il programma con lo stesso dataset già validato.
6. Controllare nel log:

   ```text
   [curvefit.family_global] rows=... solver=... RMSE=... R2=...
   standard_octave: output contract satisfied (... declared files)
   ```

7. Controllare che esistano ancora:

   ```text
   fit_parameters.csv
   fit_summary.txt
   fit_predictions.csv
   render_cache.mat
   ```

8. Eseguire il rerender dei grafici senza rilanciare il fit.
9. Verificare entrambi i Graph Provider output abilitati.
10. Solo dopo integrare la modifica nella versione principale.

---

## 8. Mappa rapida delle funzioni del file

```text
curvefit_family_global_main()   orchestrazione completa del fit
arg_value()                     parsing CLI
read_ini()/ini_get()            lettura runtime.ini
read_named_csv3()               lettura dataset CSV
fit_fminsearch()                solver fallback
bounded_sse()                   costo con bounds per fminsearch
write_parameters()              fit_parameters.csv
write_predictions()             fit_predictions.csv
write_summary()                 fit_summary.txt
render_family()                 dispatch Graph Provider
render_overlay()                measured vs fitted
render_residuals()              grafico residui
apply_optional_limits()         limiti X/Y specifici del grafico
```

---

## 9. File da consegnare a chi deve modificare il fitter

Minimo indispensabile:

```text
curvefit_family_global_main.m
```

Utile come riferimento dell'interfaccia:

```text
module.ini
GXTXT_PLUGIN_MODULE_INTERFACE_SPEC_v077.md
```

Se la modifica riguarda anche il modello Koren, aggiungere:

```text
plugins/models/triode.koren_v1/model.ini
plugins/models/triode.koren_v1/runtime/triode_koren_v1.m
```

---

## 8. Diagnostic extension: parity, relative residuals and family metrics

The diagnostic extension preserves the existing fitting objective, solvers, bounds, preprocessing, `curvefit.family.overlay` and `curvefit.family.residuals`. It adds diagnostics derived only from the already computed fitted values.

### Relative residual threshold

`minimum_abs_y_for_relative_error` is a module-level descriptor-driven parameter. Samples with `abs(Y_measured) < threshold` are excluded only from relative-error diagnostics; zero measured values are also excluded because the relative error is mathematically undefined. The original dataset and fit are not changed.

### Metrics by family

`fit_metrics_by_family.csv` contains one row for every numeric family value with:

```text
family_value,n,sse,rmse,mae,max_abs_error,r2
```

R2 is left blank when it is not meaningful because the measured Y values in that family have zero total variance (or fewer than two samples).

### Rerender cache

The cache retains the legacy variables `x`, `family`, `y`, `pred` and additionally stores explicit aliases and diagnostic data including `X`, `Y_measured`, `Y_fitted`, `residual`, `relative_residual_percent`, the relative-error mask/threshold and metrics by family. PNG files remain derived artifacts.

## PLOTS

```text
curvefit.family.overlay
curvefit.family.residuals
curvefit.family.parity
curvefit.family.relative_residuals
curvefit.family.error_by_family
```

The existing overlay and residual plots remain enabled by default. The three diagnostic plots are offered but disabled by default.

## RESULTS / OUTPUT

```text
fit_parameters.csv
fit_summary.txt
fit_predictions.csv
fit_metrics_by_family.csv
render_cache.mat
```

Graph Provider PNG files are intentionally not duplicated in `[outputs].files`.

---

# Fit / Evaluate extension (plugin version 2)

The plugin now supports `operation_mode=fit|evaluate`. `fit` is the backward-compatible default. `evaluate` uses frozen parameters from either `fixed_parameter_values` or `parameter_csv_path` and bypasses the optimization branch entirely.

`presentation_orientation=x_by_family|family_by_x` is presentation-only. The mathematical model always receives the semantic bindings in the order `(theta, x, family)`.

No GX-TXT core changes are required for this extension: all new controls use existing Module API v1 descriptor field types.

---

# Training-domain diagnostics (plugin version 3)

Version 3 adds a persistent description of the training region and separates validation metrics from extrapolation metrics without changing the numerical fit/evaluate algorithms.

## Domain definition

The training domain is defined only in the two-dimensional mathematical-model input plane:

```text
(model x, model family)
```

Fit mode computes the convex hull with Octave `convhull`. The informational bounding box and measured-Y range are stored in the sidecar but are not used for classification.

The primary sidecar is:

```text
fit_domain.csv
```

It contains model identity, model-input binding names, training count, informational ranges, numerical tolerance, and ordered convex-hull vertices.

## Parameter/domain association

For `parameter_source=csv`, Evaluate resolves the requested `fit_parameters.csv` first and then looks for:

```text
<same-directory>/fit_domain.csv
```

No 6BX7/Koren path or parameter name is hard-coded. If the sidecar is absent, evaluation remains backward compatible: the model is evaluated normally and every `domain_role` is `unknown`.

## Point classification

Evaluate classifies every point with `inpolygon` in physical model-input order `(x,family)`. Points returned on the polygon boundary are in-domain. A small normalized point-to-edge tolerance also protects mathematical boundary points against floating-point rounding.

Classification is performed before `presentation_view()`. Therefore `x_by_family` and `family_by_x` cannot change the in/out result.

## Domain metrics

`fit_metrics_by_domain.csv` contains:

```text
domain_role,n,sse,rmse,mae,r2
```

for `all`, `in_domain`, `out_of_domain`, and `unknown`. Empty categories use `n=0` and blank numeric fields.

`fit_metrics_by_family.csv` is left unchanged. The cross-classification requested for diagnostics is written separately as:

```text
fit_metrics_by_family_domain.csv
```

## Scientific meaning

`in_domain` means interpolation inside/on the convex hull of the model-input training points. It does not assert that a datum is correct.

`out_of_domain` means extrapolation outside the convex hull. It does not assert that a datum is wrong.

Measured Y is never an input to the in/out classification.

---

# GX-TXT Pipeline v0.7.8 compatibility addendum — plugin version 4

Plugin version 4 keeps Module API 1 and Graph Provider API 1 but adopts the new backward-compatible v0.7.8 services.

Changes:

- `parameter_csv_path` uses descriptor type `file` with the generic framework Browse control;
- parameter CSV loading uses `gxtxt_read_parameter_set`;
- `fit_domain.csv` uses the Shared Model-Domain CSV format with stable input names `x,family`;
- model-domain reading/validation/classification uses `gxtxt_read_model_domain`, `gxtxt_validate_model_domain`, and `gxtxt_classify_model_domain`;
- `fit_domain.csv` is a conditional sidecar and is not part of the mandatory checked `[outputs].files` list, because Evaluate can legitimately run with an old parameter set that has no domain;
- the plugin uses Progress API v1 helpers for analysis and rerender stages;
- the optimizer remains indeterminate to avoid changing the established solver path merely to expose an iteration callback;
- no core change is required.

The mathematical fit objective, bounds, solver selection, semantic model argument order and five graph IDs remain unchanged.
