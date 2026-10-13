# Sources and provenance

This Session combines real public cartographic layers with a synthetic hydraulic demonstration. The hydraulic field is not an observation or calibrated model.

## Normalized analysis envelope

- Working CRS: ETRS89 / UTM zone 32N (`EPSG:25832`).
- Fixed local origin: E = 458000 m, N = 4995000 m.
- UTM envelope: E 458000..526000 m; N 4995000..5075000 m.
- Approximate WGS84 envelope: lon 8.45927055..9.33474193; lat 45.10722069..45.82807311.
- Regular grid: 68 x 80 = 5440 cells, exactly 1 km x 1 km.
- Main analytical/visual corridor: cell-centre distance <= 20 km from the derived Ticino route (3578 grid cells).

## Terrain

Copernicus DEM GLO-30, 2021 release. The source is a digital surface model, not a bare-earth DTM. Source horizontal CRS EPSG:4326 and EGM2008 vertical datum. The acquired bundle contains a 30 m EPSG:25832 derivative produced by nearest-neighbour horizontal reprojection. The normalized grid stores mean, minimum and maximum elevation aggregated from that real raster.

Required attribution: produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.

## Population

ISTAT 2021 regular 1 km population grid, CC BY 4.0. Source grid is EPSG:3035. Population is area-weighted from intersecting official source cells onto the normalized EPSG:25832 1 km grid. This is not a substitution with municipal totals. Reference year: 2021.

## Land cover

CORINE Land Cover 2018, catalogue V2020_20u1; the queried official REST snapshot does not independently expose a package version stamp. Source: European Union's Copernicus Land Monitoring Service information; DOI 10.2909/71c95a07-e296-44fc-b22b-415f42acfdf0. Fractions are exact target-cell polygon-area fractions. Built/artificial uses CLC level-1 artificial classes; forest uses 311/312/313 only; agriculture uses the documented CLC agricultural classes; water uses 511/512 only. Wetlands and other semi-natural classes are not silently reassigned.

## Hydrography

Regione Lombardia, Reticolo Idrografico Regionale Unificato (RIRU), official AIPO main-watercourse layer, Fiume Ticino OBJECTID 6, CC BY 4.0. A north-to-south shortest path through unsimplified source vertices is used only as an ordered chainage candidate. It is not an authoritative channel choice in braided sections.

## Settlements

ISTAT Basi Territoriali 2021, Localita Puntuali, CC BY 4.0. The demonstration subset keeps inhabited centres and inhabited nuclei (`TIPO_LOC` 1/2) with actual source `POP21 >= 50` and distance <= 20 km from the Ticino route. Population values are never inferred.

## Hydraulics

`raw/ticino_hydraulic_demo.csv` is synthetic. Real route geometry and DEM values provide spatial context only. The generated bed/water/depth/velocity field is deterministic and exists only to exercise GX-TXT spatial analysis and 3D graphics. It is not a 2-D shallow-water simulation, CFD result, flood model, calibration or prediction.

## Acquisition bundle

Source bundle: `ticino_valley_source_bundle_20260923.tgz`
SHA-256: `0500172477a05bd24f11444e0302a5cea270d7335b170ee0b3b4f9a3dd380541`
Retrieval date recorded by source bundle: 2026-09-23.

Source details and terms of use are documented in `source_bundle_manifest.tsv`, `ATTRIBUTIONS.md`, and `CORINE_CLASSIFICATION.md`.
