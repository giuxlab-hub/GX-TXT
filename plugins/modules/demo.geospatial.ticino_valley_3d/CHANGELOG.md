# Changelog

## 2.0.0

- Publishes terrain, river, settlements, population, four land-cover fractions and synthetic hydraulics as nine persistent public Plot.dataset 3D variants.
- Removes the private Octave figure renderer and keeps each layer's axis and color scale independently editable in the framework.
- Retains full-resolution source-derived numerical reports and scientific validation; the display views use canonical Dataset variable IDs.

## 1.0.1

- Resolve expected canonical column names to the imported Dataset's stable `variable_id` values before opening Table Stream v3. This fixes analyses of real GX-TXT imports, which assign IDs such as `v0001` rather than using CSV headers as IDs.
- Make the runtime fixture use normal `v000N` IDs so this compatibility regression is covered by tests.

## 1.0.0

* Added four-source GX-TXT geospatial analysis module for the Ticino Valley 3D Session Generator.
* Added validated grid/population/land-cover/river/locality summaries and four cartographic views.
* Marked the hydraulic field as synthetic throughout and added cache-only rerendering.
