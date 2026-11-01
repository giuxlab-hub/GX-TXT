# Scientific Spectrum Preview 1.0.1

This Builder-authored compiled C++ Preview consults the current canonical
spectrum.scientific Dataset through matching P033 CORE public facilities.
Its interface and source are included in the normal package. The module is
independent of importer identity/version. Enable it through ordinary Preview
Configuration; installation does not silently enable a newly installed Preview.

Plot uses the maintained public Plot owner and every admitted canonical point.
Axis defaults come from declared coordinate/quantity semantics. When these are
absent, choose actual X and Y Variables explicitly. Native Plot controls own
Fit/Zoom/navigation; source values and scientific payload stay unchanged.

Values has explicit First/Previous/Next Variable, values page and Variable batch
controls. First Variable is user enumeration. Exact C-order hyperslabs contain
at most512cells per request. CORE renders actual coordinate refs, dtype/units and
exact canonical numeric text including uint64, with source-bound page indices.
Metadata and Source tabs have their own First/Previous/Next batch controls.
Source distinguishes pinned CORE identity from original decoded source headers;
multiline legal/provenance metadata is retained by the canonical owner.

Only existing public CORE Plot, numeric-array and metadata services are used.
Unavailable, malformed, stale or oversized operations explicitly refuse and
retain the current source. This private candidate still requires actual native,
scientific, GUI, cold and independent qualification. Generic headless Test is a
compiled no-owner-context smoke; it cannot establish these feature gates.

Version 1.0.1 places binding controls in the existing Source tab and compacts existing local paging controls. The default Plot uses the whole declared notebook page. Source, numerical data, handlers, role identities and SDK remain unchanged; actual shared CORE viewport behavior and independent acceptance are separate.
