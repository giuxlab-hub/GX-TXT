# IR Spectroscopy — Reference Evidence

Open **IR References** and use the Browser's Records, Sources and Manual pages to search,
page and inspect a reference, its rights and its exact source. Installation,
updates and removal belong to the normal Library Manager. Use published
Library archives, never owner safety copies. Choose **Compare → Add selected
IR reference**, then **Prepare comparison**. A single reference supports
Overlay, Top/Bottom or Stacked consultation without creating a Session.
When this Viewer was opened for a Library reference, **Add opened IR reference**
admits that exact current reference explicitly; it does not guess a replacement.

The layout uses the public IR-scoped Scientific Library Browser's Records,
Sources and Manual pages and the shared Comparison Plot. Library administration
stays in its existing Manager; this module owns no importer, registry or parser.
Comparison supports raw Overlay, independent-Y Top/Bottom, declared Stacked
display offset, ordered Difference and Ratio. Source samples remain unchanged;
normalization is explicit display state, and a similarity score is not a
probability or independent chemical identification. Optical absorption index k
must never be described as absorbance.

CORE owns canonical Dataset/Variable/source identity, Library paging and rights,
Numeric arithmetic, native Plot, Workspace/History and the original IR Analysis
runner. The C++ implementation routes finite declared public intents only.

With a real Session open, choose **Compare → Discover sources**. On Sources,
select the measured Dataset and actual X/Y Variables, then Add Dataset source.
Inspect physical units and ordinate meaning. Wavenumber, wavelength, absorbance,
optical absorption index *k*, and transmittance fraction/percent are distinct.
Unknown metadata is not a conversion. Comparison and Analysis have separate
explicit Dataset selections; a processed Analysis output never silently replaces
the original measured Comparison source.

Enable the existing IR Spectroscopy and Reference Matching Analysis module
through normal module controls. In **Analysis → Input**, choose the measured
Dataset and **Analysis → Discover Analysis source**, then bind Spectral X and
Measured Y. Confirm the ordinate representation; its initial value is a proposal.
Enter actual installed reference Library IDs, semicolon-separated if several.

Processing contains the wavenumber range in cm^-1, baseline method/degree,
smoothing method/window, normalization, derivative order and matching-grid step.
Matching contains score method, fingerprint bounds/weight, peak prominence and
tolerance, candidate count and minimum match score. Review these actual Analysis
parameters for the physical measurement and retain them when reporting results.

**Run Analysis** explicitly submits to the normal Analysis queue. **Analysis
status** reads that invocation; **Cancel owned Analysis** cancels it. Opening,
page changes and Workspace restore never run it. After completion choose **Read
ranked references**. The horizontally scrollable table shows stable rank,
Library/version/content identity, entry/material, scores, range and warnings.
Its page is zero-based, with 25 rows/page and at most 100 ranked results. Select
a real row/rank, then **Add selected ranked reference**. Current source/result
revisions are checked again; stale results require review or a fresh Analysis.

The source list retains explicit order, identity and units, up to eight sources.
Use Remove/Move and choose a method, then Prepare comparison. Top/Bottom has
independent Y panels; Stacked uses an explicit display offset. Difference is
first minus second, Ratio is first divided by second with an explicit denominator
floor. Both require two compatible sources, linear alignment on their common
intersection and the first source's grid, with no hidden extrapolation.
Display normalization/derived curves do not rewrite source samples.

The Plot menu provides Fit, Zoom, display-value cursor, reverse X, Properties,
Legend, Series style, Copy, PNG Export and Session Plot Variants. Native pan/zoom,
axes, labels, colors and export retain the shared Plot owner. Reverse X changes
presentation, not canonical ordering; a display cursor is not a canonical sample.

Use ordinary Session Workspace and scientific History controls to preserve and
review selection/configuration. Restore neither reruns Analysis nor silently
replaces a revised Library reference. Session switching/closing invalidates its
Dataset-backed context; open a fresh Viewer for the new context. Dataset Analysis,
Variants, Session Workspaces and History require a real Session; pure Library
consultation does not fabricate one.

Requires P035 CORE capabilities for Browser-selected comparison, targeted
Analysis, provenance-qualified IR opening and Library-only Plot consultation.
Automatic IR opening requires canonical spectrum_kind=IR and
x_quantity=wavenumber; unknown/RF/FFT/NMR is not auto-classified IR. Archive
availability does not prove a full 9537-reference validation. RefIMP Item13
self-match is retrieval consistency, not independent identification. NIST *k*
must not be relabeled absorbance.

Maintained references: COMPARISON_PLOT_API_v1, MODULE_TARGETED_ANALYSIS_API_v1,
PLOT_DATASET_API_v4, SCIENTIFIC_LIBRARY_MANAGER_API_v1,
CONTRACT_VISUALIZER_API_v1, SESSION_WORKSPACE_API_v1, SCIENTIFIC_RECIPE_API_v1.

All source is GPL-3.0-or-later. This package contains no scientific Library,
measured data or third-party measurement redistribution. Proper published
Library archives and their actual rights/provenance must be inspected through
the normal Manager; owner safety copies are not installation inputs.
