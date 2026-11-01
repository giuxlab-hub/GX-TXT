# Actual validation results

Executed by `scripts/validate_bundle.py` on the processed files. PASS means the check ran and succeeded; SKIP is intentional.

| Result | Check | Evidence |
|---|---|---|
| PASS | Required files present | 13 files |
| PASS | Metric study extent readable and EPSG:25832 | [ 456727.05780955 4994115.45184655  526750.54654764 5075306.67472146] |
| PASS | Terrain native_4326 known CRS | EPSG:4326 |
| PASS | Terrain native_4326 finite elevations | 8420112 valid pixels; min=48.50; max=1145.12 |
| PASS | Terrain projected_25832 known CRS | EPSG:25832 |
| PASS | Terrain projected_25832 finite elevations | 6264565 valid pixels; min=48.50; max=1145.12 |
| PASS | Metric terrain resolution retained | (30.0, 30.0) |
| PASS | Population layer readable and EPSG:25832 | 5810 cells, CRS=EPSG:25832 |
| PASS | Population source IDs unique | 5810 IDs |
| PASS | Population nonnegative | min=0, sum of whole selected cells=5696819 |
| PASS | CORINE layer readable and EPSG:25832 | 2438 polygons, CRS=EPSG:25832 |
| PASS | CORINE official classes only | ['111', '112', '121', '122', '124', '131', '132', '133', '141', '142', '211', '213', '221', '222', '231', '242', '243', '311', '312', '313', '321', '324', '331', '411', '412', '511', '512'] |
| PASS | CORINE geometries nonempty | 2438 polygons |
| PASS | CORINE covers study area | sum of clipped polygon area / study area = 1.00000 |
| PASS | Official river readable and EPSG:25832 | 1 feature |
| PASS | Derived route readable and EPSG:25832 | 1 feature |
| PASS | River reaches outlet and confluence | outlet distance=0.0 m; confluence distance=0.1 m |
| PASS | Candidate route ordered north-to-south | length=110.27 km; endpoints=(470835.7579995098, 5063409.943895243) -> (518168.30050029943, 4998604.259995219) |
| PASS | Settlements readable and EPSG:25832 | 2261 places, CRS=EPSG:25832 |
| PASS | Settlement names and actual POP21 | 2261 names; 2261 source population values |
| PASS | Settlement coordinates in study extent | 2261 within WGS84 rectangle |
| PASS | Requested corridor inside study extent | Sesto Calende outlet, Vigevano, Abbiategrasso, Pavia, Ticino-Po confluence |
| PASS | Manifest output SHA-256 matches | 7 manifest rows |
| PASS | License and attribution recorded | 4 source/license documents |
| SKIP | Optional hydrology observations | ARPA Lombardia SIDRO evaluated; suitable station series and exact redistribution terms not confirmed, so no data included |
