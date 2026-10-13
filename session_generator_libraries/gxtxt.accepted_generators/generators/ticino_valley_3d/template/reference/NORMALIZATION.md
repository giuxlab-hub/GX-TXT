# Normalization notes

The four CSV files in `raw/` are normalized demonstration resources derived once from the documented public-source bundle. Session generation itself performs no network access and no GIS processing.

## Cartographic grid

The grid is a complete 68 x 80 rectangular EPSG:25832 lattice with 1 km cells and local plotting coordinates:

```text
x_km = (easting_m - 458000) / 1000
y_km = (northing_m - 4995000) / 1000
```

`in_study_corridor=1` means the cell centre is within 20 km of the derived ordered Ticino route. Values outside the corridor remain in the Dataset so the rectangular surface topology is preserved; the demo plugin masks them from the principal corridor statistics and surface views.

Population is allocated by source-cell/target-cell intersection area. CLC fractions are intersection area divided by the exact 1 km² target-cell area. DEM mean/min/max are aggregated from the real 30 m projected GLO-30 derivative. `distance_to_ticino_km` is Euclidean distance in EPSG:25832.

## Settlements

The subset is deterministic: ISTAT locality type 1 or 2, actual `POP21 >= 50`, inside the normalized envelope and within 20 km of the Ticino route.

## River

The candidate RIRU route is sampled every 250 m of metric chainage and at the final endpoint. Terrain reference elevation is sampled from the real DEM.

## Synthetic hydraulics

The hydraulic ribbon contains 112 longitudinal stations and 5 lateral offsets, for 560 points. Hydraulic quantities are deterministic synthetic values. Water surface is exactly `bed_elevation_m + water_depth_m`, depth and velocity are non-negative, and the nominal longitudinal water-surface drop in this synthetic field is 142.500000 m.
