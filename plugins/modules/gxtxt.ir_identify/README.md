# gxtxt.ir_identify v2.0

IR protocol identification module for GX-TXT Pipeline.
License: **GNU GPL v3 or later**.

## Architecture

The module does not reinterpret the raw analog waveform. It consumes the deterministic output of `gxtxt.ir_waveform v3.3`:

`waveform -> carrier + MARK/SPACE -> protocol identification -> optional payload decoding`

Run `gxtxt.ir_waveform` first for the same dataset and primary signal. The identifier locates the matching `ir_analysis_manifest.ini` in the current session and uses its measured carrier and `eventi_mark_space.csv`.

## Protocol definitions

Initial protocol table: `protocols/protocols_ir_v1.csv`.

The table is data-driven for the protocol families supported by the generic engines:

- NEC family — pulse distance;
- Samsung — pulse distance;
- Panasonic / Kaseikyo — pulse distance;
- Sony SIRC — pulse width;
- Philips RC5 — biphase;
- Philips RC6 — biphase with header.

The table records carrier, header timing, symbol timing, bit counts and bit order. New protocols that fit one of the existing modulation families can be added without embedding their numerical timings in the scoring engine.

## Identification result

Every candidate is scored. Lower is better. The report preserves the individual score contributions where applicable:

- measured carrier mismatch (with the expected carrier retained explicitly in the candidate CSV/report);
- header timing error;
- data-symbol timing error;
- MARK timing error;
- SPACE timing error;
- bit-count error;
- biphase timing error.

The module can return:

- `ACCEPTED` — best score is good enough and clearly ahead of the runner-up;
- `AMBIGUOUS` — best candidate is plausible but insufficiently separated from the runner-up;
- `UNKNOWN` — no candidate reaches the acceptance threshold.

This prevents the mathematically best candidate from being presented as a certain identification when all matches are poor.

## Measured carrier

The identifier uses the **measured carrier** from `gxtxt.ir_waveform`, not the user-supplied nominal value. The expected carrier of each protocol is only one score component.

Therefore a waveform entered with an incorrect nominal frequency can still be identified correctly after v3.3 adaptive carrier recovery.

## Outputs

- `protocol_identification.txt`
- `protocol_candidates.csv`
- `protocol_timing.csv`
- `protocol_frame.csv`
- `render_cache.mat`

The analysis publishes four canonical diagnostic Datasets (candidate scores,
timing comparison, MARK/SPACE events and decoded frame). Graphs use persistent
public Plot.dataset Plot Variants. Their presentation can be edited through the
normal plot window and rerendered without identifying the protocol again.
Scoring uses the advertised `math.numeric` statistics and reduction API.

For supported LSB-first protocols, decoded bits and bytes are reported. NEC-family payload complement checks are retained from the historical V1 program.

## Diagnostic graphs

- `irid.ranking` — all protocol candidates ranked by score;
- `irid.timing` — measured versus expected timings for the best candidate;
- `irid.clusters` — MARK/SPACE timing fingerprint with expected timing references;
- `irid.frame` — real measured frame timeline with header and decoded bit labels where available.

The frame graph labels the header and representative bits for a readable default
view. The complete decoded sequence remains in `protocol_frame.csv`.
The graphs are diagnostic evidence for the identification, not a substitute for the numerical report.

## Historical source

The published `GXTXT_identifica_protocollo_IR_v1.m` was used as a functional design trace. v2.0 is not a line-for-line copy: it adapts the useful concepts to the Standard Module API, separates protocol data from the engine, exposes score components, supports UNKNOWN/AMBIGUOUS results and adds graphical diagnostics.
