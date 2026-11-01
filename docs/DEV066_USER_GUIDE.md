# dev-066 remote X11 workflow

Use the Page selector above the notebook for complete page names and keyboard
navigation. Sessions contains the existing Session, Import / Export,
Configuration and Tools menus and five content views.

Curve Workbench opens inside the available screen with visible idle viewport
icons and a complete footer. Create a Spline with successive clicks; Enter or
Finish commits it, and Escape returns to Select. Moving the pointer back to the
last placed point keeps the valid preview. Use Settings to show the left utility
area and its scrollbars, and Sketch palette to inspect relationships. Pan, wheel
zoom and Fit all remain available on the viewport toolbar.

Parameters and graphical dimensions retain the dev-065 behavior: a Workspace
formula such as `session.base * 2` can drive an 8 mm dimension when Session
`base=4`. Save Workspace before closing. Reopen it from Session Workspaces; its
retained objects and bindings restore. Portable Session export/import includes
that state. See DEV065_USER_GUIDE.md for the full retained-network workflow and
reports/REMOTE_X11_dev066.md for the tested display and actual evidence.

Loading configuration or creating/importing another Session preserves the APIs
already installed in this application process. Viewer and parameter actions
continue to work after these ordinary Session operations.

Curve Fit starts within the remote screen allowance and requests explicit placement before mapping, keeping its residual/footer area above native taskbars on the tested display.

Curve Fit reserves the report, status and residual table/paging rows before allocating the plot. The residual checkbox shows/hides exact tabular residuals; the plot uses the remaining space.
