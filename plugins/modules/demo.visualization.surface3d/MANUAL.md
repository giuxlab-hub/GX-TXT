# 3D Surface Visualization Demo — Manual

## Purpose

`demo.visualization.surface3d` is a deliberately small GX-TXT demonstration of the framework's existing 3D scientific plotting path. It is not a general mathematical plotting module. Its intended workflow is a finite rectangular scientific Dataset followed by framework-native `surface`, `mesh`, and `contour3` rendering.

The default generated Dataset contains only 41 × 41 = 1681 points so that rendering, rerendering, viewpoint changes, color changes, and regression testing remain practical. Large time-frequency results are intentionally outside the scope of this demo.

## Framework and installation

The plugin requires GX-TXT 0.9.7.77 or later.

Install the current `demo.visualization.surface3d` plugin package through the normal Plugin Install interface. The plugin remains external (`core=0`) and does not modify the framework distribution.

The deterministic Session Generator is supplied separately as `surface3d_thermal_field_1.0.0.zip` and is also bundled inside the plugin under `bundled/`. Open the Session Generator Library Manager, select **GX-TXT Numerical Examples**, choose **Import Generator...**, and import that ZIP.

## Synthetic thermal model

The generator creates a steady-state temperature field over a rectangular plate:

```text
T(x,y) = 293.15
       + 18*exp(-((x+12)^2/(2*9^2) + (y-8)^2/(2*12^2)))
       + 11*exp(-((x-16)^2/(2*14^2) + (y+10)^2/(2*8^2)))
       + 0.03*x
       - 0.02*y
```

`x` and `y` are millimetres and `T` is kelvin. There is no random noise.

The coordinate ranges are:

```text
X = -50 mm ... +50 mm
Y = -50 mm ... +50 mm
```

with 41 positions per axis and 2.5 mm spacing. The complete grid contains 1681 points, ordered with Y as the outer loop and X as the inner loop.

## Generated Session files

The generator creates:

```text
raw/thermal_surface_3d.csv
metadata/thermal_surface_3d.metadata.txt
reference/thermal_surface_truth.txt
```

GX-TXT also writes normal Session Generator provenance to `metadata/session_generator.ini`.

The CSV columns are:

```text
x_mm
y_mm
temperature_K
```

The metadata file uses Dataset Metadata API v1 portable import syntax. The first `=` separates key from value, therefore the analytical equation can itself contain additional `=` characters without ambiguity.

The reference truth file exists only for deterministic validation. The normal plugin never reads it.

## Recommended import workflow

1. Generate a Session with **GX-TXT Numerical Examples → Visualization → 3D Thermal Surface**. The suggested Session name is `surface3d-demo`.
2. Import `raw/thermal_surface_3d.csv` with the normal generic CSV acquisition path.
3. Open **Variables** and verify/save the canonical Variable Schema.
4. Assign the coordinate quantities as numeric variables with units `mm`; assign temperature unit `K`. The X/Y coordinate variables should have the normal independent-coordinate semantic role and temperature should be measured data.
5. Open **Metadata... → Import...**, select `metadata/thermal_surface_3d.metadata.txt`, review the fields, and select **Save**.
6. Enable **3D Surface Visualization Demo** in Analysis.
7. Select the imported Dataset as the primary Analysis Source.
8. Bind **X coordinate**, **Y coordinate**, and **Z value** to the stable Dataset variable IDs corresponding to X, Y, and temperature.
9. Run the module.

Canonical variable IDs, not CSV headers, are the persisted technical identities used by Analysis Source bindings.

## Rectangular-grid requirements

Before plotting, the plugin reads only the three selected variables through Table Stream API v3 and verifies:

- X has more than one unique coordinate;
- Y has more than one unique coordinate;
- all X/Y pairs are unique;
- row count is exactly `unique(X) × unique(Y)`;
- every expected grid cell exists;
- X, Y, and Z are finite;
- coordinates can be resolved deterministically to ascending X and Y vectors.

The plugin does not interpolate missing points and does not convert scattered XYZ data into a grid. Invalid data produce an explicit diagnostic.

## Summary calculations

The plugin uses `NUMERIC_API_v1` descriptive statistics for the Z values and reports:

- point count;
- X grid size;
- Y grid size;
- minimum temperature;
- maximum temperature;
- mean temperature;
- temperature range;
- X/Y coordinate of the maximum temperature.

The outputs are:

```text
surface3d_report.txt
surface3d_metrics.ini
```

The source Dataset is not duplicated or republished.

## Automatic graphs

A normal Run generates three Graph Provider outputs from the same prepared grid.

### Surface

Graph ID:

```text
demo.visualization.surface3d.surface
```

Artifact:

```text
01_surface.png
```

This uses public `gxtxt_plot_surface()` from Plot 3D API v2. Temperature is also used as the color quantity. A colorbar is enabled by default unless a graph-specific/common graphics setting explicitly overrides it.

### Mesh

Graph ID:

```text
demo.visualization.surface3d.mesh
```

Artifact:

```text
02_mesh.png
```

This uses public `gxtxt_plot_mesh()` on exactly the same scientific grid.

### 3D contour

Graph ID:

```text
demo.visualization.surface3d.contour3
```

Artifact:

```text
03_contour3.png
```

This uses public `gxtxt_plot_contour3()`. The default is 12 contour levels and can be changed through the graph configuration.

## Axes and units

With the generated Dataset and source units, the automatic labels are:

```text
X position [mm]
Y position [mm]
Temperature [K]
```

The renderer does not manually scale `mm` or `K`. It uses the current Unit/Dimension and graphics display-unit infrastructure. Compatible presentation-unit changes remain presentation state; the Dataset is not rewritten.

## Color and viewpoint

The module uses the shared GX-TXT graphics settings for:

- colormap;
- colorbar visibility and label;
- color limits;
- azimuth;
- elevation;
- projection where supported;
- axes/grid presentation.

No plugin-private viewpoint or colormap registry exists.

The default viewpoint follows the current GX-TXT graphics configuration. Graph-specific Axes/3D settings override inherited defaults through the normal framework mechanism.

## Render Cache and rerender

The first Run validates the grid, calculates statistics, stores only Dataset identity and small validation metadata in the Render Cache API v1 payload, and creates public Plot.dataset 3D variants.

Presentation-only changes such as azimuth, elevation, colormap, colorbar, color limits, axis presentation, or compatible display units use the normal plot window and persistent Plot.dataset variant. Rerender reads the canonical Dataset through the shared bounded 3D preparation path. The scientific validation and statistics are not recalculated when a valid render cache is available.

If the source Dataset fingerprint changes, rerender rejects the stale cache and requires a normal Run.

## Manual `plot.dataset.xyz` workflow

The demo does not hide the 3D graphics path. The same imported source Dataset can be plotted manually with the bundled `plot.dataset` module:

1. Enable **Scientific Dataset Plot**.
2. Select the same Dataset.
3. Bind X = the X coordinate variable, Y = the Y coordinate variable, Z = temperature.
4. Enable `plot.dataset.xyz`.
5. Choose `surface`, `mesh`, or `contour3` as the 3D plot type.
6. Run or rerender through the normal plotting workflow.

The rectangular-grid requirements are intentionally compatible with `plot.dataset.xyz` gridded rendering.

## Expected deterministic reference values

For the default 41 × 41 generator, the reference values are approximately:

```text
point count       = 1681
minimum T         = 290.650005297855 K
maximum T         = 310.708246164604 K
mean T            = 295.044889217262 K
maximum location  = X -12.5 mm, Y 7.5 mm
```

The generator stores higher-precision reference values in `reference/thermal_surface_truth.txt`.

## Performance observations

The default grid is intentionally small. Rendering time is recorded only as an observation when the real Octave render test is run; no fragile timing threshold is used. In the packaging environment used for release 1.0.2, GNU Octave was unavailable, so actual surface/mesh/contour3 timing is reported as `SKIP` rather than estimated.

## Limitations

- rectangular grids only for the automatic surface, mesh, and contour3 demonstration;
- no interpolation of missing cells;
- no scattered-to-grid conversion;
- no volumetric rendering;
- no 3D selection resource;
- projection capabilities depend on the active Octave graphics toolkit;
- the plugin is a visualization demo, not a general field-processing module.

## Public GX-TXT APIs used

- Standard Module API v1;
- Analysis Source Map API v1;
- Analysis Source Metadata Runtime Extension v1;
- Analysis Source Dataset Metadata Runtime Extension v1;
- Table Stream API v3;
- NUMERIC_API_v1;
- Graph Provider API v1;
- Scientific Plot Framework API v1;
- Plot 3D API v2;
- Graphics Inheritance API v1;
- Render Cache API v1;
- Unit Selector / Unit-Dimension APIs;
- Dataset Metadata API v1;
- Plugin Install API v1;
- Session Generator Library API v1.

## Validation

Generator and package-validation checks can run without Octave. Numerical
grid checks and PNG rendering require a working GNU Octave installation; when
it is unavailable, they must be reported as `SKIP` rather than `PASS`.


## Stable variable identity

The Analysis Source selector may display canonical variable names such as `x_mm`, `y_mm`, and `temperature_K`. These display/canonical names are not used as Dataset technical identities. At runtime the plugin resolves every binding through `gxtxt_analysis_source_variable_meta()` and passes the returned stable `variable_id` to Table Stream API v3 together with the selected `dataset_id`. This is required because imported Datasets commonly use stable IDs such as `v0001` even when their canonical names are human-readable column names.
