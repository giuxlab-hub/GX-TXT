# GX-TXT Shared Parameter-Set API v1

GX-TXT Pipeline v0.7.8.

## Formato compatibile

Il formato minimo rimane:

```csv
parameter,value
p1,1.25
p2,8
```

Metadata `model_id` è opzionale. Sono accettati:

```text
# model_id=my.model
```

o una colonna opzionale `model_id`.

## Helper

```octave
ps = gxtxt_read_parameter_set(path, expected_names, expected_model_id)
ps = gxtxt_validate_parameter_set(ps, expected_names, expected_model_id)
```

`ps` contiene:

```text
path
names
values
model_id
```

## Validazioni

- header `parameter,value` obbligatorio;
- nomi vuoti vietati;
- valori devono essere numerici e finiti;
- duplicati vietati;
- se `expected_names` è fornito: parametri mancanti/inattesi sono errori;
- output riordinato esattamente come `expected_names`;
- `model_id` viene verificato solo quando è disponibile sia nel file sia nel consumer.

Per un model plugin GX-TXT, l'ordine atteso è quello di `[parameters] names=` esposto nel runtime come `model.param_names`.
