# Session-free native Plot display API v1

Discover `NATIVE_PLOT_DISPLAY_API_v1@1` through the normal CORE catalog. The small
adapter in `core/tcl/native_plot_display_v1.tcl` asks the existing public
`PLOT_DATASET_API_v4::modelFromSpec` owner to validate a prepared RAM model. The
same native Plot v4 token and `GXNativeSurface` Cairo painter used by ordinary
Plot widgets render it. The protected Plot module is unchanged.

```tcl
set plot [::GX::nativePlotDisplayCreate .viewer.canvas.plot \
    [::GX::viewerGuiDemoPlotModel] callback]
pack $plot -fill both -expand 1
::GX::nativePlotDisplayView $plot zoom 1.25
::GX::nativePlotDisplayView $plot fit
set receipt [::GX::nativePlotDisplayInspect $plot]
::GX::nativePlotDisplayDestroy $plot
```

The optional trusted callback receives actual bounded synthetic selection/view
events. Pointer wheel zooms; middle drag pans; double-click fits; ordinary click
performs real native hit testing. `nativePlotDisplayHit widget x y` returns that
native result. Inspect identifies `PLOT_DATASET_API_v4`, native C++/Cairo renderer,
empty source identity, RAM provenance, publication0 and actual paint receipt.

Bounds are eight displays, 1MiB input, four panels, eight series per panel and
4096 points per series. Only prepared RAM line, line_marker and scatter series
are admitted. Dataset IDs, source descriptors and cell-field bindings are
refused; arbitrary canonical or user files cannot enter this fixture path.
Destroy cancels the owned idle paint and releases only its native Plot token.
Neither resize nor navigation publishes a Dataset, changes units or evaluates
an Analysis. Scientific Plot binding continues through its original owner.
