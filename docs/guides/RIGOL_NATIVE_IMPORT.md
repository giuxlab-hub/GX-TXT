# Native Rigol CSV Import — `acq.rigol_csv`

GPL-3.0-or-later

`acq.rigol_csv` is a native Standard Module API v1 acquisition module in v0.6.1. It is no longer registered as `legacy_adapter`.

The module descriptor owns parser/layout configuration. The existing `gxtxt_csv_worker.m` is retained as the scientific/streaming engine because it is already proven on large oscilloscope CSV files; reusing an implementation does not make the module legacy as long as the public configuration and outputs obey the standard module contract.

## Configuration

Descriptor fields include parser, delimiter, header rows, sequence/time columns, manual `tStart`/`dt`, chunk size, record shape and strict sequence checking.

## Variables

Channel/quantity assignment is no longer a predefined ProvaTelecomando mapping. The Variables tab defines enabled source columns and canonical names. For Rigol, `Source channel` may contain values such as `CH1`, `CH2`, etc.

Example:

```text
CSV column 2 -> source channel CH1 -> canonical variable Va_V
CSV column 3 -> source channel CH2 -> canonical variable Vg_V
```

After a successful worker run, available channel outputs are registered in `metadata/datasets.ini` with `source_module=acq.rigol_csv`.

## Instruments

The Rigol importer does not automatically create an oscilloscope record. If instrument provenance is wanted, add the actual oscilloscope in Instrumentation and associate variables with its stable ID/channel.
