# One-time preprocessing

`build_normalized_reference.py` is the exact preprocessing program used to create the normalized CSV resources from `ticino_valley_source_bundle_20260923.tgz` in the development environment. It uses GeoPandas, Rasterio, Shapely, PyProj, NumPy and Pandas. The installed Session Generator does not execute it and has no GIS dependency; it copies the already normalized resources as a template.

The script records the fixed EPSG:25832 envelope, 1 km grid, area-weighted ISTAT population allocation, CLC area fractions, DEM aggregation, ordered river sampling and deterministic synthetic hydraulic field.
