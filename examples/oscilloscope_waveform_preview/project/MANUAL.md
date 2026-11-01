# Oscilloscope waveform

Enable this module in Module/Plugin Manager. Open a compatible Dataset in
Dataset Preview and select its controls tab alongside the standard display.
Dataset and Session changes retire the old pane and callbacks. Disabling,
updating or closing the module disposes its controls and viewport panels.

## Authoring and callbacks

Open gui/design.tcldict in Viewer Interface Builder with the Preview Module
target. The Builder display is a layout simulation; test the installed
package inside Dataset Preview for actual Dataset and viewport behavior.
Edit handlers.tcl; regeneration preserves its exact bytes. Preview handlers
receive (host, event). Inspect datasetPreviewGuiContext and use the public
datasetPreviewGuiControlGet/Set/Configure/State operations for controls.
Bound fit/zoom actions use the existing Plot controller. Other unconnected
actions report an error. Explicit user actions may call authorized services;
mount and disposal do not run science or publish Datasets. Optional
Handlers::dispose(context, reason) releases author-owned timers/resources.
The expired host cannot be reused during disposal.

Compatibility uses the declared Dataset contracts and optional metadata
filters. A viewport panel requires an available public Plot viewport;
unsupported sources report that limitation while retaining standard Preview.
Native Viewer surfaces, Workspace/History and menu hosts have no Preview
component admission. Use supported UI Field containers and actions.
