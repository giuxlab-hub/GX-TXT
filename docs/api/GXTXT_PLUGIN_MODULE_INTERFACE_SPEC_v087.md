# GX-TXT Pipeline v0.8.5 — Specifica completa per moduli e plugin

SPDX-License-Identifier: GPL-3.0-or-later

**Versione di riferimento:** GX-TXT Pipeline v0.8.5  
**Module API:** 1  
**Instrument Module API:** 1  
**Graph Provider API:** 1  
**Plot Annotation API:** 1  
**Scientific Analysis Definition API:** 1  
**Render Cache API:** 1 (optional)  
**Contract Registry API:** 1  
**Manifest:** Format 2

---


## 0A. Estensione normativa v0.8.5 — Analysis Source Map API v1

GX-TXT v0.8.5 aggiunge alla Standard Module API v1 il supporto additivo a **N dataset sorgente** per un singolo modulo di analisi. I moduli esistenti basati su `dataset_id` restano invariati.

Un modulo opt-in dichiara:

```ini
[analysis_sources]
api_version=1
ids=primary;uncertainty
dynamic=1

[analysis_source.primary]
required=1
contracts=curve_family.table

[analysis_source.uncertainty]
required=0
contracts=table.generic
```

Il framework genera la tabella GUI `Source ID / Dataset ID`, persiste la mappa nel Manifest Format 2, risolve i path canonici nel runtime e mostra binding qualificati `source.variable`.

Compatibilità binding:

```text
x=Vg1_V                 -> primary.Vg1_V
sigma_y=uncertainty.sigma_total
```

Il layer non esegue join, interpolazione, resampling o allineamento automatico. Tali operazioni restano esplicite nella Scientific Analysis Definition API.

Helper Octave pubblico:

```octave
sources = gxtxt_analysis_source_map_from_runtime(runtime_cfg);
```

Normativa completa: `docs/api/ANALYSIS_SOURCE_MAP_API_v1.md`.

## 0. Estensioni normative v0.8.4

GX-TXT v0.8.4 mantiene Standard Module API v1, Scientific Analysis Definition API v1 e Manifest Format 2, ma aggiunge contratti additivi importanti:

- **Documentation API v1 obbligatoria per plugin nuovi/aggiornati**; i plugin legacy senza sezione `[documentation]` restano caricabili in v0.8.4 con warning, ma versioni future possono applicare il requisito silenziosamente;
- Scientific Analysis parameter GUI generata da `[parameters]`, con persistenza Manifest/runtime;
- preflight generico per Analysis Definitions;
- `align`, `join`, `resample`, `interpolate`;
- `peak/extrema`, `integrate/area`, `derivative/slope`, `window`;
- `correlate`, `regress`, `fit` come bridge verso Mathematical Model Plugin API;
- Unit/Dimension API v1 minima, con controllo `strict_units=1` opt-in e `convert_unit`;
- operation registry/kernel dispatcher interno;
- Render Cache API v1 estesa con fingerprint standard e conversione del risultato Scientific Analysis in cache envelope;
- riferimento installato generabile dai descriptor;
- policy di uncertainty formalizzata, senza propagazione generale ad-hoc.

Documentazione normativa da consultare:

```text
docs/api/DOCUMENTATION_API_v1.md
docs/api/SCIENTIFIC_ANALYSIS_DEFINITION_API_v1.md
docs/api/RENDER_CACHE_API_v1.md
docs/api/UNIT_DIMENSION_API_v1.md
docs/api/UNCERTAINTY_POLICY_v1.md
docs/api/CONTRACT_REGISTRY_API_v1.md
docs/guides/SCIENTIFIC_ANALYSIS_AUTHORING_GUIDE.md
```

Per Axes/Grid, gli override finali restano centralizzati nel framework tramite `gxtxt_print_png_atomic()` e il finalizer comune. Nessun plugin deve introdurre workaround locali per Grid. La legenda continua a usare la shared graphics API esistente.

### Documentation API: requisito di conformità

Un plugin nuovo/aggiornato DEVE dichiarare almeno:

```ini
[documentation]
api_version=1
guide=README.md
api_refs=MODULE_API_v1
examples=
changelog=
```

La v0.8.4 mantiene retrocompatibilità con descriptor più vecchi che omettono questa sezione, registrandoli come `legacy_missing`. Questo comportamento non deve essere assunto da plugin nuovi: una versione futura può non esporre/eseguire normalmente plugin privi della documentazione richiesta.

## 1. Scopo del documento

Questo documento è la specifica unica da rispettare quando si aggiunge un nuovo modulo o plugin a GX-TXT Pipeline v0.8.4.

Consolida i contratti attualmente distribuiti fra:

- Standard Module API v1;
- Canonical Dataset API v1;
- Graph Provider API v1;
- Module Plot Configuration API v1;
- Graphics Inheritance API v1;
- Instrument Module API v1;
- Plot Annotation API v1;
- Manifest Format 2;
- struttura fisica del framework v0.8.4.

Il documento descrive **il comportamento realmente previsto dalla v0.8.4**, non una API futura ideale.

Dove viene usato il linguaggio normativo:

- **MUST / DEVE**: requisito obbligatorio per essere conforme;
- **MUST NOT / NON DEVE**: comportamento vietato;
- **SHOULD / DOVREBBE**: fortemente raccomandato;
- **MAY / PUÒ**: facoltativo.

---

# 2. Principio architetturale fondamentale

GX-TXT Pipeline è un framework descriptor-driven.

Un nuovo modulo non deve richiedere l'aggiunta di pannelli, rami di coda o logica scientifica dentro il core.

La separazione prevista è:

```text
framework core
    │
    ├── discovery descriptor
    ├── GUI generata
    ├── Manifest Format 2
    ├── Canonical Dataset API
    ├── runner standard
    ├── Graph Provider
    ├── graphics / legend / annotations
    └── print / export

plugin/module
    │
    ├── descriptor
    └── runtime scientifico specifico
```

Il core non deve conoscere a priori il significato scientifico di un nuovo modulo.

---

# 3. Tipi di plugin discoverable nella v0.8.4

La v0.8.4 espone moduli, modelli, strumenti e Scientific Analysis Definitions discoverable.

## 3.1 Moduli scientifici / importatori

Directory:

```text
plugins/modules/<module-id>/
```

Descriptor obbligatorio:

```text
plugins/modules/<module-id>/module.ini
```

Runtime opzionale ma normalmente presente:

```text
plugins/modules/<module-id>/runtime/
```

Un modulo può avere:

```text
kind=acquisition
```

oppure:

```text
kind=analysis
```

---

## 3.2 Modelli matematici

Directory:

```text
plugins/models/<model-id>/
```

Descriptor:

```text
plugins/models/<model-id>/model.ini
```

Runtime tipico:

```text
plugins/models/<model-id>/runtime/
```

I modelli sono risorse matematiche selezionabili da un modulo di analisi; non sono job autonomi.

---

## 3.3 Moduli strumento

Directory:

```text
plugins/instruments/<instrument-id>/
```

Descriptor:

```text
plugins/instruments/<instrument-id>/instrument.ini
```

Un instrument plugin descrive **uno schema di metadati** di uno strumento, non un dispositivo reale e non un algoritmo di acquisizione.

---

## 3.4 Cosa NON è un plugin discoverable

Le directory:

```text
core/
services/
```

non sono plugin directory.

`services/annotations` e `services/printing` sono servizi condivisi del framework.

Un nuovo tipo arbitrario di plugin sotto `services/` non viene scoperto automaticamente.

---

# 4. Struttura fisica del pacchetto

La v0.8.4 usa questa struttura:

```text
gxtxt_pipeline_v084/
├── gxtxt_pipeline.tcl
├── README.md
├── CHANGELOG.md
├── LICENSE
├── core/
│   ├── tcl/
│   └── octave/
│       ├── analysis/
│       ├── cache/
│       ├── graphics/
│       ├── io/
│       ├── util/
│       └── legacy/
├── plugins/
│   ├── modules/
│   ├── models/
│   └── instruments/
├── services/
│   ├── annotations/
│   └── printing/
├── docs/
│   ├── api/
│   ├── guides/
│   ├── architecture/
│   └── validation/
├── examples/
└── tests/
```

## 4.1 Ownership

`core/`:

- DEVE contenere solo infrastruttura generale;
- NON DEVE contenere algoritmi scientifici specifici di un modulo.

`plugins/modules/<id>/`:

- possiede il descriptor del modulo;
- possiede il runtime scientifico del modulo.

`plugins/models/<id>/`:

- possiede il descriptor e il codice del modello matematico.

`plugins/instruments/<id>/`:

- possiede lo schema metadati dello strumento.

`services/`:

- contiene servizi applicativi riutilizzabili non scientifici.

---

# 5. Regole generali per gli ID

Ogni plugin DEVE avere un ID stabile e non vuoto.

Esempi correnti:

```text
acq.generic_csv
acq.rigol_csv
curvefit.family_global
triode.koren_v1
instrument.oscilloscope
```

Il loader della v0.8.4 verifica almeno:

- ID non vuoto;
- unicità dell'ID nella propria classe;
- `api_version=1`.

La notazione minuscola separata da punti è la convenzione usata dal framework e DOVREBBE essere mantenuta per i nuovi plugin.

L'ID non deve dipendere da:

- testo tradotto;
- etichetta GUI;
- nome di un file temporaneo;
- nome di una specifica sessione.

---

# 6. Discovery

La discovery avviene automaticamente da:

```text
plugins/modules/*/module.ini
plugins/models/*/model.ini
plugins/instruments/*/instrument.ini
```

Non esiste un registry centrale da aggiornare per queste tre classi.

Un descriptor assente o con API non supportata non deve essere considerato disponibile.

---

# 7. Standard Module API v1 — descriptor `module.ini`

## 7.1 Struttura minima di un modulo di analisi

```ini
[meta]
api_version=1
id=my.analysis.module
kind=analysis
name=My Analysis Module
version=1
runner=standard_octave
selectable=1
default_enabled=0

[inputs]
contracts=my.dataset.contract

[outputs]
files=result.csv;summary.txt

[graphs]
ids=

[config]
fields=dataset_id

[config.dataset_id]
type=dataset
label=Input dataset
default=
required=1
```

---

## 7.2 Sezione `[meta]`

Campi letti dal framework:

```text
api_version
id
kind
group
name
version
selectable
default_enabled
enabled_key
run_key
runner
order
depends
description
config_hint
```

### Campi fondamentali

`api_version`:

```ini
api_version=1
```

DEVE essere `1` nella v0.8.4.

`id`:

ID stabile del modulo.

`kind`:

```text
acquisition
analysis
```

`runner`:

runner riconosciuto dal profilo corrente.

Per i nuovi moduli di analisi nativi:

```text
standard_octave
```

Per gli importer nativi correnti:

```text
standard_tcl
```

### Campi di presentazione

`group`:

raggruppamento GUI.

`name`:

nome leggibile.

`description`:

descrizione del modulo.

`config_hint`:

breve aiuto visualizzato nella configurazione.

`order`:

intero usato per ordinare i moduli. Se non è valido viene trattato come `1000`.

### Selezione

`selectable=1`:

il modulo può essere abilitato/disabilitato dall'utente.

`selectable=0`:

modulo gestito da un altro meccanismo, tipicamente acquisition selection.

`default_enabled`:

stato iniziale per un nuovo esperimento.

`depends`:

lista di module ID dipendenti. La selezione del modulo abilita le dipendenze dichiarate.

---

# 8. Input contract dei moduli

Un modulo DEVE dichiarare il tipo di dataset accettato:

```ini
[inputs]
contracts=curve_family.table
```

Possono essere dichiarati più contract usando la sintassi di lista già usata dal framework.

Un modulo di analisi non deve dedurre la provenienza del dato dal nome della directory, dal nome del file o da un particolare strumento.

Il contract descrive **che tipo di dataset serve**, non chi lo ha prodotto.

Esempi correnti:

```text
raw.csv
curve_family.table
timeseries.table
```

---

# 9. Canonical Dataset API v1

Ogni sessione registra i dataset in:

```text
metadata/datasets.ini
```

Un dataset contiene almeno concetti quali:

```text
id
kind / contract
format
path
columns
source_module
provenance/hash quando disponibili
```

## 9.1 Regola fondamentale

I moduli di analisi DEVONO consumare dataset canonici e variabili canoniche.

Non devono dipendere direttamente dal layout originale del file acquisito, salvo che siano essi stessi moduli di importazione.

---

## 9.2 Variabili canoniche

Per un CSV generico, il comportamento predefinito è:

```text
header CSV -> stesso nome canonico
```

L'utente può definire:

```text
canonical name
unit
semantic role
source column
source channel
instrument ID
instrument channel/terminal
```

Esempio:

```text
header originale: Voltage
canonical:        Va_V
unit:             V
semantic_role:    independent
instrument_id:    scope_main
instrument_channel: CH1
```

Un alias canonico non deve essere soltanto cosmetico: l'importer generico scrive realmente il nome canonico nell'header del dataset derivato.

Il RAW originale non viene modificato.

---

# 10. Source Variables nel Manifest Format 2

Le variabili vengono persistite come:

```ini
[source_variables]
count=3

[source_variable.1]
enabled=1
source_column=1
source_channel=
original_header=X_V
canonical=Va_V
unit=V
semantic_role=independent
instrument_id=scope_main
instrument_channel=CH1
```

Campi correnti:

```text
enabled
source_column
source_channel
original_header
canonical
unit
semantic_role
instrument_id
instrument_channel
```

Un analysis plugin NON DEVE leggere direttamente questa struttura per inventarsi mapping proprietari se può usare il binding standard.

---

# 11. Configurazione descriptor-driven

Le chiavi configurabili vengono dichiarate in:

```ini
[config]
fields=dataset_id;solver;max_iter
```

Ogni chiave ha una sezione:

```ini
[config.solver]
type=choice
label=Solver
default=auto
values=auto;lsqnonlin;fminsearch
required=1
```

## 11.1 Tipi supportati dal Module API

La documentazione e i descriptor correnti usano/supportano:

```text
string
integer
double
choice
boolean
dataset
model
```

Un nuovo modulo DOVREBBE usare solo tipi già supportati dal framework.

Non deve aggiungere widget specifici direttamente in `gxtxt_pipeline.tcl`.

## 11.2 Campi comuni di una configurazione

A seconda del tipo possono essere usati:

```text
type
label
default
required
values
contract
```

`values` è usato per `choice`.

`contract` può restringere il dataset selezionabile.

---

# 12. Input binding semantico per moduli di analisi

Un analysis module DEVE dichiarare **che cosa gli serve**, non una posizione CSV hard-coded.

Esempio:

```ini
[bindings]
roles=x;family;y

[binding.x]
label=Independent X
required=1
preferred_model_field=x_column
semantic_role=independent

[binding.family]
label=Family variable
required=1
preferred_model_field=family_column
semantic_role=family

[binding.y]
label=Measured Y
required=1
preferred_model_field=y_column
semantic_role=measured
```

## 12.1 Ordine di risoluzione

Il framework risolve una variabile con questo ordine:

```text
1. binding esplicito dell'utente
2. variabile preferita dichiarata dal modello matematico
3. variabile canonica con semantic_role compatibile
4. errore se il ruolo è required e resta irrisolto
```

Questo consente di usare lo stesso modulo con:

- CSV generico;
- dati Rigol;
- acquisizioni future;
- dataset prodotti da altri moduli.

---

# 13. Manifest delle configurazioni di modulo

La configurazione viene salvata in:

```ini
[module_config.<module-id>]
...
```

Esempio:

```ini
[module_config.curvefit.family_global]
dataset_id=curve_family.primary
model_id=triode.koren_v1
solver=auto
max_iter=2000
tolerance=1e-8
```

I binding vengono salvati separatamente:

```ini
[module_binding.curvefit.family_global]
x=auto
family=auto
y=auto
```

Un plugin non deve richiedere che il core conosca queste chiavi in anticipo.

---

# 14. Moduli di analisi `standard_octave`

## 14.1 Descriptor runner

```ini
[meta]
runner=standard_octave
```

Il runtime del modulo viene dichiarato in:

```ini
[runner]
script=plugins/modules/my.module/runtime/my_module.m
rerender_script=plugins/modules/my.module/runtime/my_module_rerender.m
```

I path sono relativi alla root del pacchetto.

---

## 14.2 Runtime generato dal framework

Il framework genera un `runtime.ini` nella directory di output del modulo.

Il runtime contiene concettualmente:

```text
[runtime]
[dataset]
[model]               se applicabile
[config]
[binding.* / binding state]
[plot.<graph-id>]
[graph_provider]
[legend.<graph-id>]
[graphics_effective]
```

Il modulo deve trattare il runtime come contratto di esecuzione corrente.

Il runtime viene rigenerato per riflettere lo stato grafico/presentazione corrente prima dei rerender nativi.

Il modulo NON DEVE usare variabili di configurazione legacy non dichiarate dal proprio descriptor.

---

# 15. Contratto degli output

## 15.1 Output non grafici

Un analysis module dichiara gli output obbligatori non grafici:

```ini
[outputs]
files=fit_parameters.csv;fit_summary.txt;fit_predictions.csv;render_cache.mat
```

Per `standard_octave`, questi file sono un **contratto eseguibile**.

Dopo l'esecuzione il wrapper verifica che esistano.

Il job fallisce se:

- Octave termina con stato non zero;
- manca un output obbligatorio.

Un semplice `runtime.ini` non è prova di completamento del modulo.

---

## 15.2 Output grafici

Con Graph Provider API, i PNG offerti NON devono essere duplicati in `[outputs].files`.

Il framework aggiunge automaticamente al contratto i file dei graph ID abilitati.

---

# 16. Graph Provider API v1

Un analysis module può dichiarare un catalogo arbitrario di grafici.

Esempio:

```ini
[graphs]
provider_api_version=1
ids=my.module.main;my.module.residuals;my.module.spectrum
default_ids=my.module.main;my.module.residuals
rerender=standard_octave
```

Ogni graph ID DEVE avere una sezione:

```ini
[graph.my.module.main]
name=Main graph
default_enabled=1
file=01_main.png
config_fields=title;x_label;y_label
```

## 16.1 Regole

`ids`:

catalogo completo di graph ID offerti dal modulo.

`default_ids`:

grafici abilitati in un nuovo esperimento.

`default_enabled`:

può definire/rafforzare lo stato del singolo grafico.

`file`:

nome deterministico dell'output grafico.

`rerender`:

runner standard usato per il rerender.

## 16.2 Una istanza per graph ID

Graph Provider API v1 supporta intenzionalmente **una sola istanza configurata per graph ID**.

Se servono più varianti indipendenti, il modulo DEVE dichiarare graph ID distinti.

Esempio:

```text
filter.bode.full
filter.bode.magnitude
filter.bode.phase
```

invece di creare dinamicamente N istanze dello stesso ID.

---

# 17. Selezione grafici nel manifest e runtime

Manifest:

```ini
[graph_provider_api]
version=1

[module_graphs.my.module]
offered=my.module.main,my.module.residuals
enabled=my.module.main
```

Runtime:

```ini
[graph_provider]
api_version=1
offered=my.module.main;my.module.residuals
enabled=my.module.main
```

Il renderer DEVE generare solo i graph ID presenti in `enabled`.

Un grafico disabilitato non deve essere considerato parte dell'esperimento corrente, anche se un vecchio PNG rimane fisicamente su disco.

---

# 18. Configurazione di un graph descriptor

Esempio:

```ini
[graph.my.module.main]
name=Main result
file=01_main.png
config_fields=title;x_label;y_label;show_points;line_width

[graph.my.module.main.config.title]
type=string
label=Plot title
default=Main result

[graph.my.module.main.config.show_points]
type=boolean
label=Show measured points
default=1

[graph.my.module.main.config.line_width]
type=double
label=Line width
default=1.5
```

I controlli vengono generati dal descriptor.

NON aggiungere controlli specifici del grafico direttamente al core GUI.

---

# 19. Manifest dei parametri specifici del grafico

Ogni grafico ha una sezione:

```ini
[module_plot.<module-id>.<graph-id>]
...
```

Questi valori vengono copiati nel runtime come:

```ini
[plot.<graph-id>]
...
```

Il primo render e il rerender devono usare lo stesso contratto.

Il rerender deve poter modificare la presentazione senza ripetere il calcolo numerico quando il modulo dispone di cache sufficiente.

---

# 20. Graphics Inheritance API v1

La presentazione comune ha una gerarchia obbligatoria:

```text
1. Global graphics
2. Module graphics override, se abilitato
3. Plot-specific override
```

Un livello più specifico prevale solo per i campi che imposta realmente.

Valori vuoti o `inherit` DEVONO ricadere sul livello padre.

---

## 20.1 Global graphics

Il profilo globale è comune a tutti i moduli e include concetti quali:

```text
width / height
dpi
font unit
font sizes
line width
grid
grid color
background
legend defaults
```

È configurato dalla GUI `Plots -> Global graphics...`.

Il DPI globale dei PNG nativi è:

```text
graphics.analysis_png_dpi
```

Un modulo non deve duplicare il DPI come parametro scientifico privato salvo che produca un raster scientificamente distinto che richieda realmente una risoluzione propria.

---

## 20.2 Unitá font

La configurazione globale usa:

```text
px
pt
```

Per il font legenda:

```text
inherit
px
pt
```

`inherit` segue l'unità font globale effettiva.

Semantica:

```text
px = pixel nel PNG finale, convertiti internamente in punti usando il DPI
pt = punti tipografici
```

Il framework è responsabile della conversione.

---

## 20.3 Override modulo

Se un modulo offre grafici, può avere:

```ini
[module_graphics.<module-id>]
enabled=1
dpi=300
font_unit=pt
font_size=9
legend_font_unit=px
legend_font_size=10
grid_mode=inherit
background=
```

L'override modulo è disabilitato di default.

Un campo vuoto/`inherit` conserva il valore globale.

Il modulo non deve creare un sistema di stile parallelo se il parametro è già coperto dalla Graphics Inheritance API.

---

## 20.4 Stato effettivo

I valori risolti vengono riportati in:

```ini
[graphics_effective]
```

nel `runtime.ini`.

Il renderer dovrebbe usare lo stato effettivo fornito dal framework, non ricalcolare una propria ereditarietà incompatibile.

---

# 21. Standard Legend Editor

Un grafico che vuole la legenda comune dichiara:

```ini
[graph.<graph-id>]
supports_legend=1
legend_editor=standard
legend_placements=inside;above;below;left;right;manual
legend_layouts=row;stacked;wrapped
```

## 21.1 Placement e layout sono indipendenti

Placement:

```text
inside
above
below
left
right
manual
none
```

Layout:

```text
row
stacked
wrapped
auto
```

Alignment esterno:

```text
start
center
end
```

`location` è un preset usato solo per `inside`.

`columns` è usato da `wrapped`.

`manual_x` e `manual_y` sono coordinate normalizzate del **centro** della legenda e valgono solo per `manual`.

Configurazioni valide:

```text
below + row
below + wrapped + columns=4
right + stacked
inside + row
manual + wrapped + columns=3
```

---

## 21.2 Renderer conforme

Un modulo che dichiara `legend_editor=standard` DEVE usare il helper centralizzato:

```octave
gxtxt_plot_legend(labels, plot_config, graph_id)
```

oppure la forma con handles/runtime:

```octave
gxtxt_plot_legend(handles, labels, plot_config, graph_id, runtime_cfg)
```

NON DEVE chiamare direttamente `legend(...)` per produrre la legenda finale, perché così bypasserebbe:

- persistence;
- placement manuale;
- layout row/stacked/wrapped;
- override per plot;
- font px/pt;
- background/border;
- rerender coerente.

---

## 21.3 Overflow

Il renderer comune può ridurre il numero effettivo di colonne se una legenda `row`/`wrapped` non entra fisicamente nell'area disponibile.

Il modulo non deve implementare una seconda logica di wrapping.

---

# 22. Stato legenda nel Manifest Format 2

```ini
[plot.legend.overrides]
keys=my.module.main

[plot.legend.my.module.main]
enabled=1
placement=below
layout=wrapped
alignment=center
location=northeast
columns=4
background=#FFFFFF
border=0
border_color=#808080
font_unit=pt
font_size=9
external_margin_px=12
manual_x=0.75
manual_y=0.85
```

Semantica inheritance importante:

```text
blank / inherit -> eredita
background=none -> trasparenza esplicita
border=0 -> nessun bordo
border=1 -> bordo esplicito
```

Un campo vuoto NON deve essere interpretato come richiesta di trasparenza o disattivazione.

---

# 23. Plot Annotation API v1

Un grafico può abilitare annotazioni non distruttive:

```ini
[graph.<graph-id>]
supports_annotations=1
annotation_editor=standard
annotation_types=text;line;arrow;rectangle;ellipse
annotation_coordinate_spaces=figure_norm
```

Il modulo continua a generare solo il PNG base.

NON deve modificare il PNG per incorporare le annotazioni.

---

## 23.1 Storage

Per:

```text
analysis/<module>/01_plot.png
```

il documento standard è:

```text
analysis/<module>/annotations/01_plot.json
```

Il JSON è lo stato autorevole editabile.

---

## 23.2 Coordinate v1

La v1 implementa:

```text
figure_norm
```

con:

```text
x=0 sinistra
x=1 destra
y=0 basso
y=1 alto
```

Altri coordinate space non supportati dalla v1 devono essere rifiutati, non reinterpretati silenziosamente.

---

## 23.3 Tipi oggetto supportati

```text
text
line
arrow
rectangle
ellipse
```

Ogni oggetto contiene almeno concetti quali:

```text
id
type
visible
locked
z_index
space
```

Il testo supporta UTF-8 e font `px` / `pt`.

---

## 23.4 Export e print

La preview applica l'overlay senza modificare il PNG.

`Export annotated...` genera un nuovo PNG derivato.

Print/PDF applica automaticamente le annotazioni quando presenti.

Il modulo scientifico NON deve implementare il compositing.

---

# 24. Moduli acquisition

Un modulo acquisition usa:

```ini
[meta]
kind=acquisition
runner=standard_tcl
```

ed espone un handler:

```ini
[runner]
handler=generic_csv
```

oppure, nella v0.8.4:

```ini
handler=rigol_csv
```

## 24.1 Limite reale della v0.8.4

Questo è un punto importante.

La discovery dei descriptor è generica, ma il dispatch `standard_tcl` della v0.8.4 riconosce attualmente **solo**:

```text
generic_csv
rigol_csv
```

Quindi un nuovo algoritmo acquisition con un nuovo handler NON può oggi essere aggiunto come puro drop-in descriptor senza estendere il dispatch del core/API.

Regola:

- un nuovo importer che può essere espresso usando un handler già supportato può essere descriptor-driven;
- un nuovo tipo di handler richiede una estensione deliberata della Standard Module API/runner family;
- NON deve essere aggirato leggendo chiavi legacy casuali o inserendo branch scientifici sparsi nella GUI.

Questa è una limitazione corrente da correggere in una futura evoluzione del runner API se si vuole rendere arbitrariamente pluggable anche l'acquisition runtime.

---

# 25. Modulo `acq.generic_csv` — comportamento di riferimento

Un importer generico conforme deve mantenere questi principi:

- RAW snapshot separato;
- RAW mai modificato;
- provenance/hash quando disponibili;
- dataset canonico derivato;
- mapping delle source variables;
- registro `metadata/datasets.ini`;
- nessuna conoscenza di specifici moduli di analisi.

---

# 26. Modulo `acq.rigol_csv` — comportamento di riferimento

`acq.rigol_csv` è un acquisition module nativo ma può riutilizzare internamente il worker Octave esistente.

Il suo contratto pubblico resta descriptor-driven.

Non deve imporre automaticamente:

```text
VIR
QIN_C
OUT_PRE
HOLD
N_LED
```

né altri nomi specifici di esperimenti storici.

Le variabili vengono definite dalla Source Variable / Canonical Dataset API.

---

# 27. Mathematical Model Plugin — contratto corrente v0.8.4

La v0.8.4 scopre modelli da:

```text
plugins/models/*/model.ini
```

Non esiste nel pacchetto una guida separata denominata “Model API v1”, ma il loader e il modello `triode.koren_v1` definiscono il contratto corrente qui consolidato.

## 27.1 Esempio

```ini
[meta]
api_version=1
id=my.model.v1
kind=my_kind
name=My mathematical model
version=1
function=my_model_function
script=plugins/models/my.model.v1/runtime/my_model.m
x_column=X
family_column=F
y_column=Y
y_unit=A
description=...

[parameters]
names=p1;p2;p3
initial=1;2;3
lower=0;0;0
upper=10;10;10
```

## 27.2 Campi letti dal loader

Sezione `[meta]`:

```text
api_version
id
kind
name
version
function
script
x_column
family_column
y_column
y_unit
description
```

Sezione `[parameters]`:

```text
names
initial
lower
upper
```

Le quattro liste parametro DEVONO essere coerenti fra loro per un modello che usa bounds/initial values.

`script` è relativo alla root del pacchetto.

`function` è il simbolo richiamabile dal modulo/runner.

Le colonne preferite possono essere usate dal binding standard attraverso `preferred_model_field`.

---

# 28. Instrument Module API v1

Un instrument plugin vive in:

```text
plugins/instruments/<instrument-id>/instrument.ini
```

## 28.1 Descriptor minimo

```ini
[meta]
api_version=1
id=instrument.my_device
name=My Instrument
version=1
group=Laboratory instruments
description=...

[fields]
ids=manufacturer;model;serial;notes

[field.manufacturer]
type=string
label=Manufacturer
default=

[field.notes]
type=multiline
label=Notes
default=
```

## 28.2 Tipi campo supportati

```text
string
choice
multiline
```

## 28.3 Regole fondamentali

Un instrument descriptor:

- descrive schema/default;
- NON dichiara che un dispositivo reale è presente;
- NON crea automaticamente una istanza;
- NON implementa l'algoritmo di acquisizione;
- NON decide quali variabili usa un analysis module.

L'utente deve caricare esplicitamente il modulo dalla pagina Instrumentation.

---

# 29. Istanza strumento nel manifest

Framework-owned fields:

```text
enabled
module_id
id
display_name
```

I campi descriptor vengono salvati come:

```text
field.<name>
```

Esempio:

```ini
[instrument_module_instance.1]
enabled=1
module_id=instrument.oscilloscope
id=scope_main
display_name=Bench oscilloscope
field.manufacturer=Rigol
field.model=DS1104Z-S
field.notes=...
```

Il `id` dell'istanza è l'unico riferimento che una Source Variable deve usare per associarsi allo strumento.

---

# 30. Separazione Instrument / Acquisition / Analysis

Questi concetti NON devono essere confusi.

```text
Instrument plugin
    = che strumento è stato usato / metadati

Acquisition module
    = come importare/acquisire il dato

Canonical Dataset
    = come il dato viene esposto al framework

Analysis module
    = che elaborazione scientifica viene eseguita
```

Esempio valido:

```text
CSV Rigol
→ acq.rigol_csv
→ canonical dataset
→ Curve Family Fitting
```

senza obbligo di creare automaticamente una istanza `instrument.oscilloscope`.

---

# 31. Manifest Format 2 — sezioni rilevanti per plugin

Un plugin deve interoperare con queste aree senza inventare formati paralleli:

```text
[pipeline]
[runtime]
[acquisition]
[session]
[experiment]
[instrument_modules]
[instrument_module_instance.N]
[source_variables]
[source_variable.N]
[module_state]
[module_config.<module-id>]
[module_binding.<module-id>]
[graph_provider_api]
[module_graphs.<module-id>]
[module_plot.<module-id>.<graph-id>]
[graphics]
[module_graphics.<module-id>]
[plot.legend.overrides]
[plot.legend.<graph-id>]
[plot_annotations]
[plot_annotation.N]
[print]
```

Il manifest contiene configurazione e provenance, non codice algoritmo.

---

# 32. Experiment notebook

Il framework mantiene note esperimento separate dai plugin:

```ini
[experiment]
name=
project=
date=
operator=
tags=
notes=
objective=
procedure=
observations=
```

Le stringhe multilinea vengono rappresentate fisicamente con `\n` e ripristinate in lettura.

Un plugin non dovrebbe riutilizzare questi campi per memorizzare configurazione tecnica propria.

---

# 33. Runtime/toolchain

La configurazione runtime generale appartiene a:

```ini
[runtime]
```

Esempi:

```text
octave_cmd
cpu_count
worker_file
```

La configurazione scientifica deve invece stare nella sezione del modulo.

Non duplicare configurazioni generali/toolchain in ogni plugin se il framework le fornisce già.

---

# 34. Environment variables

Il runner standard esporta variabili generiche per graphics/runtime.

Un modulo NON DEVE richiedere che il core inietti variabili ambiente specifiche del proprio algoritmo.

La configurazione specifica del modulo deve viaggiare attraverso:

```text
module.ini
→ manifest
→ runtime.ini
```

Questo evita il ritorno a un core pieno di variabili `GXTXT_<MODULO>_*` hard-coded.

---

# 35. Rerender

Un modulo che offre rerender DEVE fornire il relativo entry point nel descriptor.

Esempio:

```ini
[runner]
rerender_script=plugins/modules/my.module/runtime/my_module_rerender.m
```

Il rerender dovrebbe usare:

- cache scientifica già calcolata;
- configurazione plot corrente;
- graphics effective corrente;
- stato legenda corrente;
- graph provider selection corrente.

Non dovrebbe ripetere il fitting/calcolo pesante se non necessario.

---

# 36. `render_cache.mat`

`render_cache.mat` non è imposto a ogni possibile modulo dall'API astratta, ma è il meccanismo attualmente usato dai moduli Octave che supportano rerender.

Se un modulo adotta questo pattern:

- il cache file deve contenere tutto ciò che serve al rerender;
- il rerender non deve dipendere da stato Tcl non serializzato;
- il PNG resta un output derivato, ricreabile dal cache + runtime corrente.

---

# 37. Path rules

I path di script nei descriptor devono essere relativi alla root del pacchetto quando usano il meccanismo corrente.

Esempio:

```ini
script=plugins/modules/my.module/runtime/my_module.m
```

Non usare:

- `/home/utente/...` hard-coded;
- path assoluti di sviluppo;
- riferimenti a `/tmp`;
- path dipendenti dalla directory corrente della shell.

Il plugin deve poter funzionare dopo estrazione del pacchetto in un'altra directory.

---

# 38. File encoding

Descriptor, INI, JSON, Markdown, CSV generati dal framework e testo plugin DOVREBBERO essere UTF-8.

Il framework corrente apre i propri registri/config testuali in UTF-8.

Per file di testo generati dal plugin è raccomandato:

```text
UTF-8
line ending LF
```

salvo formato esterno con requisiti diversi.

---

# 39. Provenance e non distruttività

Un importer deve preservare l'originale quando il contratto prevede RAW/provenance.

Un renderer non deve sovrascrivere silenziosamente dati scientifici sorgente.

Le annotazioni non devono modificare il PNG base.

I rerender devono produrre artefatti derivati in modo riproducibile.

---

# 40. GUI rules

Un plugin conforme non deve aggiungere direttamente widget scientifici specifici nel core.

Usare:

```text
[config.*]              configurazione modulo
[binding.*]             input semantici
[graph.*.config.*]      configurazione scientifica del plot
Graph Provider          selezione grafici
standard legend editor  legenda
standard annotation     annotazioni
Instrument API          metadati strumento
```

Se manca una capability generale, l'API deve essere estesa deliberatamente invece di inserire un caso speciale per un singolo modulo.

---

# 41. Cosa appartiene al modulo e cosa al framework

## Modulo

Il modulo possiede:

- significato scientifico;
- algoritmo;
- configurazione scientifica;
- input contract;
- semantic bindings richiesti;
- output scientifici;
- catalogo grafici offerti;
- logica di rendering del contenuto scientifico;
- cache necessaria al rerender.

## Framework

Il framework possiede:

- discovery;
- GUI generica;
- enable/run;
- manifest;
- dataset registry;
- variable binding;
- runner lifecycle;
- output checking;
- common graphics;
- DPI/font inheritance;
- legend editor/renderer;
- annotation editor/storage/compositing;
- export;
- print/PDF.

---

# 42. Anti-pattern vietati

Un nuovo plugin NON DEVE:

1. aggiungere un ramo specifico in `buildAnalysisQueue`;
2. leggere direttamente vecchi `cfg(...)` non appartenenti al proprio contratto;
3. hard-codare colonne come `C2`, `CH1`, `VIR`, ecc. in un analysis module;
4. inventare automaticamente strumenti reali;
5. chiamare `legend(...)` direttamente se dichiara `legend_editor=standard`;
6. incorporare annotazioni nel PNG base;
7. duplicare global graphics senza motivo;
8. usare path assoluti della macchina di sviluppo;
9. considerare il solo `runtime.ini` come prova di successo;
10. produrre graph file non deterministici rispetto al graph ID dichiarato;
11. dipendere dal testo delle etichette GUI invece che dagli ID stabili;
12. modificare il RAW originale;
13. aggiungere un nuovo graph ID richiedendo una modifica al core Tcl;
14. mescolare schema Instrument con algoritmo Acquisition.

---

# 43. Template completo — nuovo analysis module

```ini
; SPDX-License-Identifier: GPL-3.0-or-later

[meta]
api_version=1
id=example.analysis
kind=analysis
group=Generic analysis
name=Example Analysis
version=1
selectable=1
default_enabled=0
runner=standard_octave
order=500
depends=
description=Example descriptor-driven analysis module.
config_hint=Choose the dataset and configure the analysis.

[inputs]
contracts=example.table
default_dataset=example.primary

[outputs]
files=result.csv;summary.txt;render_cache.mat

[graphs]
provider_api_version=1
ids=example.analysis.main;example.analysis.diagnostic
default_ids=example.analysis.main
rerender=standard_octave

[graph.example.analysis.main]
name=Main result
default_enabled=1
file=01_main.png
supports_legend=1
legend_editor=standard
legend_placements=inside;above;below;left;right;manual
legend_layouts=row;stacked;wrapped
supports_annotations=1
annotation_editor=standard
annotation_types=text;line;arrow;rectangle;ellipse
annotation_coordinate_spaces=figure_norm
config_fields=title;x_label;y_label;line_width

[graph.example.analysis.main.config.title]
type=string
label=Plot title
default=Example Analysis

[graph.example.analysis.main.config.x_label]
type=string
label=X-axis label
default=auto

[graph.example.analysis.main.config.y_label]
type=string
label=Y-axis label
default=auto

[graph.example.analysis.main.config.line_width]
type=double
label=Line width
default=1.5

[graph.example.analysis.diagnostic]
name=Diagnostic plot
default_enabled=0
file=02_diagnostic.png
supports_legend=0
supports_annotations=1
annotation_editor=standard
annotation_types=text;line;arrow;rectangle;ellipse
annotation_coordinate_spaces=figure_norm
config_fields=title

[graph.example.analysis.diagnostic.config.title]
type=string
label=Plot title
default=Diagnostic

[runner]
script=plugins/modules/example.analysis/runtime/example_analysis.m
rerender_script=plugins/modules/example.analysis/runtime/example_analysis_rerender.m

[config]
fields=dataset_id;solver;max_iter

[config.dataset_id]
type=dataset
label=Input dataset
default=example.primary
required=1
contract=example.table

[config.solver]
type=choice
label=Solver
default=auto
values=auto;solver_a;solver_b
required=1

[config.max_iter]
type=integer
label=Maximum iterations
default=1000
required=1

[bindings]
roles=x;y

[binding.x]
label=Independent X
required=1
semantic_role=independent

[binding.y]
label=Measured Y
required=1
semantic_role=measured
```

---

# 44. Template — model plugin

```ini
; SPDX-License-Identifier: GPL-3.0-or-later

[meta]
api_version=1
id=example.model_v1
kind=example
name=Example model
version=1
function=example_model_v1
script=plugins/models/example.model_v1/runtime/example_model_v1.m
x_column=X
family_column=F
y_column=Y
y_unit=
description=Example reusable mathematical model.

[parameters]
names=p1;p2;p3
initial=1;1;1
lower=0;0;0
upper=100;100;100
```

---

# 45. Template — instrument plugin

```ini
; SPDX-License-Identifier: GPL-3.0-or-later

[meta]
api_version=1
id=instrument.example
name=Example instrument
version=1
group=Laboratory instruments
description=Metadata schema for an example instrument.

[fields]
ids=role;manufacturer;model;serial;firmware;notes

[field.role]
type=string
label=Role in experiment
default=

[field.manufacturer]
type=string
label=Manufacturer
default=

[field.model]
type=string
label=Model
default=

[field.serial]
type=string
label=Serial number
default=

[field.firmware]
type=string
label=Firmware
default=

[field.notes]
type=multiline
label=Instrument notes
default=
```

---

# 46. Checklist minima per nuovo analysis plugin

Prima di considerare il modulo conforme verificare:

- [ ] directory `plugins/modules/<id>/`;
- [ ] `module.ini` UTF-8;
- [ ] `api_version=1`;
- [ ] ID stabile e unico;
- [ ] `kind=analysis`;
- [ ] `runner=standard_octave`;
- [ ] input contract dichiarato;
- [ ] output obbligatori dichiarati;
- [ ] configurazione completamente descriptor-driven;
- [ ] binding semantici dichiarati;
- [ ] nessuna colonna/nodo storico hard-coded;
- [ ] runtime sotto la directory del plugin;
- [ ] path relativi alla package root;
- [ ] graph ID stabili dichiarati se produce grafici;
- [ ] output file deterministico per ogni graph ID;
- [ ] renderer rispetta `graph_provider.enabled`;
- [ ] legenda comune usata se dichiarata;
- [ ] annotation opt-in dichiarato se supportato;
- [ ] graphics global/module/plot inheritance rispettata;
- [ ] output contract soddisfatto;
- [ ] rerender non ripete inutilmente il calcolo scientifico;
- [ ] manifest save/reload testato;
- [ ] runtime generation testato;
- [ ] almeno un test scientifico mirato;
- [ ] nessuna modifica al core necessaria per logica scientifica del modulo.

---

# 47. Checklist minima per graph provider

- [ ] `[graphs].provider_api_version=1`;
- [ ] `ids` contiene tutti i graph ID offerti;
- [ ] ogni graph ID ha `[graph.<id>]`;
- [ ] `file=` unico e deterministico;
- [ ] `name=` leggibile;
- [ ] default state definito;
- [ ] config fields descriptor-driven;
- [ ] grafici disabilitati non vengono generati;
- [ ] grafici abilitati vengono aggiunti all'output contract;
- [ ] Plots tab riesce a mappare file -> graph ID;
- [ ] rerender supportato se dichiarato;
- [ ] legend capability usa helper comune;
- [ ] annotations capability non modifica PNG base.

---

# 48. Checklist minima per instrument plugin

- [ ] directory `plugins/instruments/<id>/`;
- [ ] `instrument.ini`;
- [ ] API 1;
- [ ] ID stabile;
- [ ] nessuna istanza reale creata automaticamente;
- [ ] soli field type supportati;
- [ ] nessun algoritmo di acquisizione nel descriptor;
- [ ] instance stable ID usato per collegamento alle variabili;
- [ ] multiline note testate;
- [ ] save/load manifest testato.

---

# 49. Checklist minima per model plugin

- [ ] directory `plugins/models/<id>/`;
- [ ] `model.ini`;
- [ ] API 1;
- [ ] ID stabile;
- [ ] funzione runtime dichiarata;
- [ ] script relativo alla package root;
- [ ] parameter names coerenti con initial/lower/upper;
- [ ] preferenze colonne dichiarate se utili al binding;
- [ ] modello indipendente dal nome di una sessione o specifico CSV;
- [ ] test matematico indipendente;
- [ ] caricamento/discovery testato.

---

# 50. Test richiesti / raccomandati

Ogni nuovo plugin dovrebbe aggiungere test mirati sotto:

```text
tests/
```

Per un analysis module, almeno:

```text
descriptor discovery
config defaults
GUI generation
manifest round-trip
binding resolution
runtime.ini generation
output contract
Graph Provider selection
rerender discovery
scientific smoke test
```

Se usa GUI Tk:

- eseguire test sotto Xvfb;
- verificare realmente che i controlli siano raggiungibili/visibili.

Se usa Octave:

- test sintattico/statico quando Octave non è disponibile;
- collaudo reale sul server Octave prima di considerare completo il modulo.

Se produce grafici:

- verificare almeno un render reale;
- verificare px/pt e DPI;
- verificare legenda se abilitata;
- verificare output multipli del Graph Provider.

---

# 51. Requisito di portabilità del pacchetto

Prima di distribuire una nuova versione:

1. creare lo ZIP;
2. estrarlo in una directory nuova;
3. eseguire discovery dalla directory estratta;
4. eseguire la suite da lì;
5. verificare che nessun path punti alla vecchia directory di sviluppo.

Questo è particolarmente importante per:

```text
[runner].script
[runner].rerender_script
model script
worker path
services
```

---

# 52. Versioning

Le versioni sono distinte:

```text
application version
module API version
instrument API version
graph provider API version
annotation API version
manifest format
plugin/module version
```

Un incremento della versione dell'applicazione non implica automaticamente un cambio di tutte le API.

Un plugin DEVE dichiarare la versione API che usa.

Una modifica incompatibile al descriptor contract dovrebbe introdurre una nuova API version invece di reinterpretare silenziosamente la precedente.

---

# 53. Compatibilità e migration

Il framework può mantenere alias di migrazione per vecchi manifesti, ma i nuovi plugin devono scrivere il formato corrente.

Esempio legenda:

campi storici come:

```text
mode
orientation
```

possono essere letti per compatibilità, ma il modello corrente usa:

```text
placement
layout
alignment
```

Un nuovo plugin non deve basarsi sugli alias legacy se esiste il campo corrente.

---

# 54. Stato delle API nella v0.8.4

## Stabili/operative nel profilo corrente

- descriptor discovery dei module plugin;
- analysis module `standard_octave`;
- Canonical Dataset API;
- semantic binding;
- model registry;
- Instrument Module API;
- Graph Provider API;
- plot descriptor configuration;
- graphics inheritance;
- standard legend service;
- Plot Annotation API;
- checked output contract;
- manifest save/reload;
- standard rerender per i moduli che lo implementano.

## Limitazione esplicita

`standard_tcl` acquisition dispatch è descriptor-selected ma non ancora un registry runtime completamente aperto: nella v0.8.4 supporta i handler nativi `generic_csv` e `rigol_csv`.

Un terzo tipo di acquisition algorithm richiede una futura estensione del runner API oppure una modifica deliberata del core dispatch.

---

# 55. Regola finale per chi sviluppa un plugin

Prima di aggiungere codice al core, chiedersi:

```text
Questa informazione appartiene davvero al framework,
o appartiene al descriptor/runtime del mio plugin?
```

Se riguarda:

```text
algoritmo
parametri scientifici
input richiesti
grafici offerti
serie da tracciare
modello matematico
```

appartiene normalmente al plugin.

Se riguarda:

```text
discovery
persistenza
binding generico
job lifecycle
graphics comuni
legend editor
annotation editor
print/export
```

appartiene normalmente al framework.

L'obiettivo della Standard Module API è che un nuovo modulo scientifico conforme possa essere aggiunto sotto `plugins/` senza trasformare `gxtxt_pipeline.tcl` in un elenco di eccezioni specifiche.

---

# 56. File di riferimento nella v0.8.4

Le specifiche originarie consolidate da questo documento si trovano nel pacchetto v0.8.4 in:

```text
docs/api/MODULE_API_v1.md
docs/api/DATASET_API_v1.md
docs/api/GRAPH_PROVIDER_API_v1.md
docs/api/PLOT_MODULE_API_v1.md
docs/api/GRAPHICS_INHERITANCE_API_v1.md
docs/api/INSTRUMENT_MODULE_API_v1.md
docs/api/PLOT_ANNOTATION_API_v1.md
docs/api/MANIFEST_FORMAT_v2.md
docs/architecture/DIRECTORY_LAYOUT.md
docs/guides/MODULE_GUIDE.md
```

Implementazione core di riferimento:

```text
core/tcl/module_api_v1.tcl
```

Plugin di esempio reali:

```text
plugins/modules/acq.generic_csv/
plugins/modules/acq.rigol_csv/
plugins/modules/curvefit.family_global/
plugins/models/triode.koren_v1/
plugins/instruments/instrument.generic/
plugins/instruments/instrument.oscilloscope/
```

Manifest di esempio:

```text
examples/example_manifest_v2.ini
```

---


# 57. Estensioni normative v0.8.4

La v0.8.4 mantiene **Module API 1** e **Manifest Format 2**. Le capability seguenti sono estensioni backward-compatible e non richiedono un nuovo `api_version` del modulo.

## 57.1 Accesso completo al mathematical model plugin

Quando un analysis module seleziona un mathematical model plugin, `runtime.ini` contiene ora anche:

```ini
[model]
id=...
function=...
script=...
descriptor_path=/.../plugins/models/<model-id>/model.ini
plugin_dir=/.../plugins/models/<model-id>
```

`descriptor_path` e `plugin_dir` sono **runtime execution data**. Non devono essere salvati come path assoluti nel descriptor del modulo.

Il core garantisce soltanto la localizzazione del model plugin. Non interpreta sezioni opzionali aggiunte al `model.ini` dal model plugin. Un consumer può quindi aprire `descriptor_path` e leggere capability aggiuntive senza introdurre conoscenza model-specific nel core.

## 57.2 Field type `file` / `path`

I campi descriptor-driven possono usare:

```ini
[config.input_file]
type=file
label=Input file
required=1
must_exist=1
extensions=.csv;.txt
dialog_title=Choose input data
```

oppure:

```ini
[config.output_dir]
type=path
path_kind=directory
label=Output directory
must_exist=1
dialog_title=Choose output directory
```

Semantica:

- `type=file` crea entry + `Browse...` per un file;
- `type=path` crea entry + `Browse...`; `path_kind=file|directory` decide il picker;
- `must_exist=1` usa un picker di apertura e valida l'esistenza prima del runtime;
- `must_exist=0` per un file usa un picker di salvataggio;
- `extensions` è una lista `;`/`,` usata come filtro GUI;
- `dialog_title` è opzionale;
- i normali `type=string` restano invariati.

La stessa UI generica è disponibile per i campi di configurazione dichiarati da un graph descriptor.

## 57.3 Shared Parameter-Set API

Gli helper ufficiali sono:

```text
core/octave/io/gxtxt_read_parameter_set.m
core/octave/util/gxtxt_validate_parameter_set.m
```

Formato base compatibile:

```csv
parameter,value
mu,8.2
Kp,61
```

È ammesso `model_id` come metadata opzionale (`# model_id=...`) o come colonna opzionale. Il reader:

- richiede `parameter,value`;
- rifiuta valori non numerici/non finiti;
- rifiuta nomi duplicati;
- se riceve l'ordine atteso del model plugin, rifiuta parametri mancanti/inattesi e riordina i valori;
- se sia file sia consumer dispongono di `model_id`, verifica la corrispondenza.

Uso tipico:

```octave
expected = strsplit(ini_get(cfg,'model.param_names',''),';');
ps = gxtxt_read_parameter_set(file, expected, ini_get(cfg,'model.id',''));
theta = ps.values;
```

## 57.4 Shared Model-Domain API

Gli helper ufficiali sono:

```text
core/octave/io/gxtxt_read_model_domain.m
core/octave/util/gxtxt_validate_model_domain.m
core/octave/util/gxtxt_classify_model_domain.m
```

Il file `fit_domain.csv` resta un CSV in cui **le colonne sono gli input del mathematical model** e le righe descrivono i punti/vertici il cui convex hull definisce il training domain. Esempio generico:

```csv
input_a,input_b
0,0
1,0
1,1
0,1
```

Metadata opzionale:

```text
# model_id=my.model
# domain_kind=convex_hull
```

La classificazione usa esclusivamente lo spazio degli input del modello. Non usa output Y, assi grafici o presentation orientation.

## 57.5 Plugin Progress API v1

La Progress API è pubblica e opzionale. Un plugin che non la usa continua a funzionare con il comportamento legacy `Running...`.

Per `standard_octave`, il framework inietta:

```text
GXTXT_PROGRESS_ENABLED=1
GXTXT_PROGRESS_MODULE_ID=<stable-module-id>
GXTXT_PROGRESS_RUN_ID=<framework-generated-id>
GXTXT_PROGRESS_OPERATION=analysis|rerender
```

Gli helper pubblici sono:

```octave
gxtxt_progress_start(stage, message, mode, total)
gxtxt_progress_stage(stage, message, mode, total)
gxtxt_progress_update(current, total, stage, message)
gxtxt_progress_complete(stage, message)
gxtxt_progress_fail(stage, message)
```

Il plugin non calcola la percentuale: `current/total` vengono normalizzati dal framework. `total<=0` o valori non validi fanno degradare la visualizzazione a indeterminate senza interrompere il job.

Gli eventi usano il protocollo riservato:

```text
@@GXTXT_PROGRESS_V1@@\tstate=...\tmode=...\tstage=...\tmessage=...\tcurrent=...\ttotal=...\tmodule_id=...\trun_id=...
```

Il core intercetta queste righe prima del normale logging. Progress e logging restano separati. In GUI il framework mostra nome modulo, stage, message e progress bar determinate/indeterminate. L'I/O del job rimane non-blocking e `fileevent`-driven.

Il lifecycle raccomandato è:

```text
start -> running/stage/update* -> completed
                            \-> failed
```

`completed` è uno stato semantico distinto dal semplice raggiungimento di `current==total`.

Gli update numerici sono throttled dall'helper: vengono emessi quando il progresso cambia significativamente, al raggiungimento del totale o dopo un intervallo temporale, evitando milioni di record per dataset grandi.

Vedi `PROGRESS_API_v1.md` per il contratto completo.

## 57.6 Runtime progress/job metadata

Il runtime dichiara il supporto:

```ini
[progress]
api_version=1
transport=structured_stdout_prefix
prefix=@@GXTXT_PROGRESS_V1@@
```

Per il singolo job il framework aggiunge:

```ini
[job]
module_id=...
run_id=...
operation=analysis
```

Gli ID di job sono framework-owned: il plugin non deve costruirli.

## 57.7 External process execution nella v0.8.4

**Non è stata introdotta una nuova External Process API.** L'analisi della base corrente non ha mostrato una necessità sufficiente per aggiungere un secondo execution layer: un plugin `standard_octave` può già lanciare un processo tramite le primitive Octave, controllare l'exit status, catturare/redirigere output, cambiare working directory in modo protetto e propagare errori al checked runner GX-TXT.

Se casi reali futuri dimostreranno la necessità di timeout/argv handling multipiattaforma condiviso, la capability dovrà essere introdotta allora come API generica. Non esiste alcun adapter SPICE/ngspice nel core v0.8.4.

## 57.8 Nessuna Artifact Dependency API

La v0.8.4 non introduce dependency graph, artifact registry cross-module, chaining automatico o staleness propagation.

## 57.9 Checklist v0.8.4 per un nuovo analysis plugin

Oltre alla checklist precedente:

1. usa `type=file/path` invece di widget Browse hard-coded;
2. usa `model.descriptor_path` / `model.plugin_dir` se devi leggere capability proprie del model plugin;
3. usa i shared helper per parameter set e model domain invece di copiarli nel modulo;
4. usa la Progress API per job lunghi, senza scrivere direttamente widget Tk;
5. mantieni progress separato dai log tecnici;
6. non costruire manualmente module/run ID;
7. non introdurre process adapter nel core per un singolo tool esterno.

# 58. Nuovi file di riferimento v0.8.4

```text
core/tcl/progress_api_v1.tcl
core/octave/io/gxtxt_read_parameter_set.m
core/octave/util/gxtxt_validate_parameter_set.m
core/octave/io/gxtxt_read_model_domain.m
core/octave/util/gxtxt_validate_model_domain.m
core/octave/util/gxtxt_classify_model_domain.m
core/octave/util/gxtxt_progress*.m
docs/api/PROGRESS_API_v1.md
docs/api/PARAMETER_SET_API_v1.md
docs/api/MODEL_DOMAIN_API_v1.md
```

**Fine della specifica — GX-TXT Pipeline v0.8.4**


# 24. v0.8.4 — Scientific Analysis Definition API v1

La v0.8.4 aggiunge una risorsa dichiarativa distinta dai modelli matematici:

```text
plugins/analysis_definitions/<definition-id>/analysis.ini
```

Un modulo può anche possedere definizioni private sotto:

```text
plugins/modules/<module-id>/analysis_definitions/<definition-id>/analysis.ini
```

Un campo di configurazione `type=analysis_definition` produce un selettore descriptor-driven. Il modulo può filtrare per `scope`, `kind` e `capabilities`. La selezione viene risolta nel `runtime.ini` con descriptor path e plugin directory.

Le definizioni sono eseguite attraverso `core/octave/analysis/gxtxt_analysis_run.m` e le primitive framework-owned. La v0.8.4 implementa `expression`, `compare`, `normalize`, `aggregate`, `filter`, `select`, export CSV/summary e plot `bar/line/scatter`.

Il wrapper di un modulo NON DOVREBBE duplicare tali operazioni. Deve risolvere le sorgenti e delegare al motore generico.

Vedere `SCIENTIFIC_ANALYSIS_DEFINITION_API_v1.md` per il contratto completo.

# 25. v0.8.4 — Graph axes/grid finalization

Per nuovi renderer Graph Provider la chiamata preferita è:

```octave
gxtxt_plot_apply_graph_axes(axs,pstyle,graph_id,panel_names,runtime_cfg)
```

La funzione applica sia lo stile comune sia gli override finali `Axes / grid...`. Il renderer non deve implementare policy locali della griglia.

La v0.8.4 ripristina inoltre il trasporto `GXTXT_PLOT_AXIS_OVERRIDE_FILE` che era stato perso dal percorso native Module API; il TSV resta fallback, mentre `[axis.<graph-id>]` nel runtime è la rappresentazione riproducibile.

---

## v0.8.6 dataset inspection / variable mapping

Plugin authors must treat canonical dataset metadata as the authoritative source of variable names. Do not parse RAW source files in an analysis plugin merely to discover headers.

For generic CSV import, Dataset Inspection / Variable Mapping API v1 provides framework-owned inspection and pre-import canonical aliases. See:

```text
docs/api/DATASET_INSPECTION_VARIABLE_MAPPING_API_v1.md
docs/guides/MULTI_DATASET_IMPORT_AND_INSPECTION.md
```

When Analysis Source Map API v1 is used, `source.variable` always names a **canonical** variable. The framework preserves original-header provenance separately.

No implicit scientific alignment is performed by import or inspection.

# v0.8.7 addendum

## Incremental canonical-dataset import

The framework owns the multi-CSV import lifecycle. Plugins continue to consume only canonical Dataset API entries. The main import may create a session; the incremental batch-import command may only add enabled Pending datasets to an already existing current session and must not create a session or clear the registry.

## Grouped Scientific Analysis rendering

Plugins and Analysis Definitions must not special-case empty/unavailable groups. The generic renderer skips zero-point line/scatter groups after framework domain/status/finite filtering and creates legend entries only for graphics primitives actually drawn.
