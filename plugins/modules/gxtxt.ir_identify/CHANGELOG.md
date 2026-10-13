# gxtxt.ir_identify changelog

## 2.0.2

- Resolves a `primary.` qualified signal binding against the waveform
  manifest's source column name, so normal GUI bindings find the preceding
  waveform analysis artifact.

## 2.0.1

- Routes reusable score statistics through public `math.numeric`.
- Publishes four diagnostic Datasets and renders all graphs with persistent
  public Plot.dataset Plot Variants, including categorical ranking ticks and
  data-coordinate annotations.
- Rerenders from small graph metadata without rescoring or rereading events.
- Keeps reference timing lines in the selected microsecond display unit and
  reduces frame labels for a readable default view.

## 2.0

Rewrite for GX-TXT Pipeline v0.7.9 Standard Module API.

- Consumes `ir_analysis_manifest.ini` and `eventi_mark_space.csv` from `gxtxt.ir_waveform v3.3`.
- Uses the measured carrier frequency from waveform analysis.
- Retains the historical V1 multi-factor protocol scoring concept.
- Moves initial protocol timings into `protocols/protocols_ir_v1.csv`.
- Adds explicit score-component output.
- Adds ACCEPTED / AMBIGUOUS / UNKNOWN result states.
- Adds candidate-ranking, timing-comparison, timing-fingerprint and decoded-frame graphs.
- Retains LSB-first payload decoding and NEC complement checks.
- Adds a synthetic NEC regression test.
