
## Dev102 retained visibility

The public native widget host adds `widgetVisibility path panelId seriesId boolean`.
It changes the existing native series display flag without rebuilding buffers,
refitting axes or reading scientific source data. Picking ignores hidden series.
Source/session revision guards remain owned by the existing Plot widget; registry
notifications and cached file stamps trigger exact source validation only when
needed. Pure visibility retains native model token, point buffers and view bounds.
