# GX-TXT Grouped Statistics

`analysis.statistics.grouped` is a production GX-TXT analysis module for descriptive statistics by one categorical or numeric grouping variable.

The module consumes a Canonical Dataset through Analysis Source, uses stable `dataset_id + variable_id` identities, reads table data through Table Stream API v3, delegates numerical statistics to `NUMERIC_API_v1`, publishes reusable derived Datasets, and optionally creates persistent `plot.dataset` variants.

Version: **1.0.0**  
License: **GNU GPL v3 or later**

See `MANUAL.md` for the scientific contract and `session_generators/gxtxt_grouped_statistics_student_lab_1.0.0.zip` for the ready-to-run teaching Session generator.
