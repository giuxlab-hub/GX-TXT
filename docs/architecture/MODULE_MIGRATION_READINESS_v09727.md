# Module migration readiness matrix

| Consumer | Current pattern | Recommended API | Difficulty | Generic CORE blocker |
|---|---|---|---|---|
| plot.dataset | whole/legacy table preparation | Table Stream v3 plus datasetAccessRequest | medium | none for selected ranges; plot-specific LOD remains |
| analysis.fft_spectrum | selected time/signal table, whole record or block | Canonical v2 or Table Stream v3; Publication v2 | medium | none |
| analysis.audio_decode | decoder produces numeric samples and CSV | Publication v2 with typed chunked output | medium | none |
| dataset.extract | table selection and CSV result | Table Stream v3 and Publication v2 Auto | low to medium | none |
| IR waveform / MARK-SPACE | legacy whole-table helpers | Table Stream v3, Canonical v2 | medium | none |
| future Equation Engine | not implemented | Canonical v2, Table Stream v3, Publication v2 | unknown | expression planning is module work |
| future Spectrogram | not implemented | Canonical ranges and HDF5 Publication v2 | unknown | transform implementation is module work |
| future CFD | not implemented | Canonical hyperslabs, Schema v3 groups/components, HDF5 | high | geometry/connectivity semantics may need a future generic contract, not proven by current fixtures |

CORE supports selected variables, chunks, direct ranges, materialization and reuse for plot.dataset; LOD/reduction remains plotting work. FFT can avoid repeated CSV prefix scanning by requesting random access and can publish large spectra through Publication v2. Audio decode can publish typed numeric chunks without a decimal CSV intermediate. dataset.extract can delegate storage choice entirely to Auto.
