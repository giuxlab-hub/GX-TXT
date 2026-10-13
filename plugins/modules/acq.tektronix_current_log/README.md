# Tektronix Current Log — `acq.tektronix_current_log`

SPDX-License-Identifier: GPL-3.0-or-later  
Produced by Giux-Lab — https://giux-lab.it

## Target

GX-TXT Pipeline **v0.8.9+**, using **Acquisition Handler Plugin API v1**.

In the GX-TXT v0.9.7.1 distribution this plugin is explicitly designated **CORE / OFF**: it is protected from uninstall but remains disabled until the user enables it. This distribution status does not change the importer algorithm or its public API.

This is a real drop-in acquisition plug-in. It does not add a new core dispatch branch and it does not write `metadata/datasets.ini` itself.

## Purpose

Import one Tektronix current-log RAW file into one canonical `timeseries.table` dataset. Typical source rows are:

```text
,,,,,28-MAY-2026,17:36:13,2819102,
,4.5311160E-01,Adc,,
...
,,,,,28-MAY-2026,19:28:28,,
```

The numeric field after the first timestamp (`2819102` in this example) is preserved as provenance text but is deliberately not interpreted.

## Framework-owned multi-file workflow

The plug-in declares `supports_batch=1`. GX-TXT therefore reuses its normal multi-source acquisition workspace:

- `Add sources...` can add an arbitrary number of files;
- every file has its own Dataset ID;
- every row has common **Preview** and **Variables** actions;
- rows are tracked as **Pending / Imported**;
- the first import creates one session;
- later Pending rows can be imported into the same current session;
- the plug-in does not implement or duplicate this lifecycle.

One file always remains one dataset. Concatenation belongs to a separate analysis/transform module.

## Inspection / Preview

`inspect_proc` recognizes the vendor structure, scans the start/end timestamp records and measurement rows, then exposes:

```text
source column 1 -> timestamp_s  [s]  semantic role: timestamp
source column 2 -> time_s       [s]  semantic role: time
source column 3 -> current_A    [A]  semantic role: measure
```

The common Variables workspace may rename canonical aliases/units/roles before import. `time_s` and the current variable must remain enabled for a valid `timeseries.table`; `timestamp_s` is optional.

The Preview rows are reconstructed canonical rows, not a Rigol preview and not a raw CSV column preview.

## Time reconstruction

For `N > 1` samples:

```text
dt = (end_timestamp - start_timestamp) / (N - 1)
time_s(i) = i * dt
```

The final sample is forced exactly to the recorded end time. `timestamp_s` is Unix epoch seconds reconstructed in `source_timezone` (default `Europe/Rome`).

No gap between different source files is removed here; different files are intentionally independent datasets.

## Configuration

- `dataset_id`: default used by single-source import; batch rows own their Dataset IDs independently.
- `campaign_id`: measurement campaign provenance tag shared by the selected import configuration.
- `series_id`: logical series provenance tag, for example `reactor_current`.
- `source_timezone`: IANA/Tcl time-zone name used for source timestamps.
- `measurement_marker`: measurement row marker, default `Adc`.

`campaign_id` and `series_id` are currently persisted in Dataset Registry `notes`/`provenance` and in the session module configuration. They do not trigger automatic grouping or joining.

## Canonical output

Default header:

```csv
timestamp_s,time_s,current_A
```

Canonical aliases selected in the Variables workspace are honored in the output CSV and Dataset Registry descriptor.

## Installation

Copy the whole directory to:

```text
plugins/modules/acq.tektronix_current_log/
```

Restart/reload GX-TXT module discovery. No core file modification is required on v0.8.9+.
