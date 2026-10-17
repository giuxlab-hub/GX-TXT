# Scientific XY Viewer

This Viewer is composed by the public CORE Viewer GUI Host.
Unbound actions report not_connected and do not start scientific Jobs.
Help displays this installed module’s manual and metadata.

## Developer handlers

Edit handlers.tcl. Each declared handler receives (window, action).
Read component values with ::GX::viewerGuiDesignValues. Use the public
Source/Plot setters, Script Job and Dataset publication services for domain work.
Keep scientific operations inside explicit handlers, never at file top level.
Regeneration preserves handlers.tcl byte for byte.
