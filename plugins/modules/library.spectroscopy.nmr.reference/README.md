# NMR Reference Library Type Provider

This provider validates managed `spectroscopy.nmr.reference` packages and exposes measured 1-D entries through the existing Scientific Library Manager. The included Cambridge package contains 24 real ¹H and ¹³C references from the University of Cambridge Apollo deposit, DOI 10.17863/CAM.130157, under CC BY 4.0. Each entry retains its original JCAMP-DX SHA-256 and processing details. The redistributed package stores a derived 1-D spectral representation with source provenance. The original upstream archive is not included.

Install `data/cambridge_co2_nmr_1d_1.0.0.zip` using the Scientific Reference Library viewer. The specialized NMR viewer owns chemical-shift presentation; the generic library browser shows library and entry metadata without NMR-specific fields.
