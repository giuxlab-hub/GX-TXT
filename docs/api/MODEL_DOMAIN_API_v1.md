# GX-TXT Shared Model-Domain API v1

GX-TXT Pipeline v0.7.8.

## Principio

Un model/training domain è definito nello **spazio degli input del mathematical model**. Non dipende dall'output Y, dall'orientamento del grafico o dalla presentazione.

Il nome compatibile `fit_domain.csv` può continuare a essere usato dai plugin.

## Formato

La prima riga contiene i nomi degli input. Le righe successive sono punti/vertici; il loro convex hull definisce il dominio.

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

## Helper

```octave
domain = gxtxt_read_model_domain(path, expected_inputs, expected_model_id)
domain = gxtxt_validate_model_domain(domain, expected_inputs, expected_model_id)
[inside, classification] = gxtxt_classify_model_domain(domain, points, tolerance)
```

`domain` contiene `input_names`, `vertices`, `kind`, `model_id`, `path`.

## Validazione

- nomi input unici;
- coordinate numeriche finite;
- dimensionalità coerente;
- almeno `D+1` punti per un dominio D-dimensionale;
- hull non dimensionalmente degenere;
- input mancanti/inattesi rifiutati quando `expected_inputs` è fornito;
- colonne riordinate secondo `expected_inputs`;
- `model_id` controllato quando disponibile.

## Classificazione

`gxtxt_classify_model_domain` usa facce del convex hull e produce:

```text
inside == true   -> classification = "inside"
inside == false  -> classification = "outside"
```

La tolleranza di default è scalata rispetto all'estensione numerica del dominio.
