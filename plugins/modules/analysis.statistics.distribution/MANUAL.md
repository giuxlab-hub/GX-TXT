# Empirical Distribution

Select a numeric Dataset variable, optionally restrict rows with a Dataset Selection, and choose a reproducible bin rule. Count uses a fixed number of equal-width bins over the selected finite data range; width uses a specified width; edges uses a strictly increasing list of explicit edges. The last edge is included in the last bin. Values outside explicit edges remain out of range and are counted in the report. Relative and cumulative frequencies use all valid observations as denominator.

The module publishes three `table.generic` Datasets: `<prefix>.bins` (frequency table with left/right edges, centers, counts and frequencies), `<prefix>.ecdf` (distinct support values, counts and cumulative probability), and `<prefix>.quantiles` (requested probability and type-7 quantile). Public `NUMERIC_API_v1` computes all three. The source Dataset is read through public Analysis Source and Table Stream interfaces and remains unchanged. Provenance includes the source stable Dataset/variable IDs, bin rule, Selection, and nonfinite policy.

The optional histogram and ECDF graphs are persistent Plot Dataset variants. Results and settings are stored in the Session. Vector results require memory proportional to the number of selected observations and distinct values.
