# GX-TXT Descriptive Statistics

`analysis.statistics.descriptive` is a production GX-TXT analysis module for descriptive statistics over one or more numeric variables in a Canonical Dataset.

It uses public Analysis Source, Dataset Selection, Table Stream, `NUMERIC_API_v1`, Dataset Publication and `plot.dataset` APIs. Automatic plots use the public `standard_octave` → `PLOT_DATASET_API_v2` bridge; no desktop bootstrap or private plot state is used. The source Dataset is never modified. Automatic histograms and box/whisker plots are persisted as normal `plot.dataset` variants and variables with incompatible units are kept in separate plots.

A portable Session Generator API v1 package, `session_generators/gxtxt_descriptive_statistics_student_lab_1.0.0.zip`, creates a ready-to-run deterministic teaching Session.

Version: 1.1.0  
License: GPL-3.0-or-later

See `MANUAL.md` for configuration, outputs, numerical definitions, graphs, teaching Session and limitations.
