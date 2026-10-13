# analysis.spectroscopy.uvvis

GX-TXT production UV/Vis spectral-family quantitation module.

Version 1.1.1 keeps the scientific workflow in the analysis module while reusable mathematics comes from `math.numeric` / `NUMERIC_API_v1` and all scientific result graphics are persistent `plot.dataset` variants.

The family overlay uses the canonical long-form `spectrum.family` Dataset directly through public numeric 2-D family grouping. It does not create one private renderer or one copied Dataset per curve. When absorbance blank correction is requested, the corrected family is a normal derived Dataset because the scientific values themselves have changed.

See `MANUAL.md` and [the architecture overview](../../../ARCHITECTURE.md).
