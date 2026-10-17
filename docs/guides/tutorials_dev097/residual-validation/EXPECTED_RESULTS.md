# Expected results — terrain residual validation

These values are supplied only as acceptance references for the deterministic tutorial Dataset.

## Global metrics

```text
count          891
bias           5.019892719486732e-13 m
MAE            0.4655834027055019 m
RMSE           0.5755625967901292 m
max abs error  1.9941355027327745 m
R2             0.9987124806014481
```

Small last-digit differences caused by numerical backend/platform details are acceptable.

## Per-profile reference

| Profile | Y [m] | N | Bias [m] | MAE [m] | RMSE [m] | Max abs [m] |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0 | 81 | 0.0165322891 | 0.4702472220 | 0.5757298612 | 1.3610480470 |
| 2 | 5 | 81 | -0.0491347212 | 0.4504635230 | 0.5576829721 | 1.3927576841 |
| 3 | 10 | 81 | 0.0526361573 | 0.4465369870 | 0.5663438067 | 1.5380771242 |
| 4 | 15 | 81 | -0.0562825194 | 0.4807004660 | 0.6156537897 | 1.9941355027 |
| 5 | 20 | 81 | 0.0702318865 | 0.4790305615 | 0.6028502305 | 1.5630278989 |
| 6 | 25 | 81 | -0.0040078593 | 0.4923437982 | 0.6138989686 | 1.6230627370 |
| 7 | 30 | 81 | -0.0288876761 | 0.4434090135 | 0.5262759045 | 1.3865183672 |
| 8 | 35 | 81 | -0.0833031765 | 0.4767795421 | 0.5845049088 | 1.7136497336 |
| 9 | 40 | 81 | 0.1428533368 | 0.4912304925 | 0.5914314115 | 1.6115987734 |
| 10 | 45 | 81 | -0.0718204854 | 0.4518001651 | 0.5380667267 | 1.2566567421 |
| 11 | 50 | 81 | 0.0111827682 | 0.4388756588 | 0.5509316539 | 1.5199154997 |

The acceptance target is the framework-computed result, not byte-identical reproduction of these decimal strings.
