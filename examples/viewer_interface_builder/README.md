# Runnable Viewer Interface Builder examples

These are synthetic developer demonstrations, separate from acquired science.
Install the ZIPs through Configuration → Modules → Plugin Manager. They require
dev104 or later and remain removable external modules. The same inert designs
can be opened in Viewer Interface Builder; generated source/handler contracts
are included in each expanded package.

- A: minimal scientific shell, an explicitly unconnected Inspect hook, typed
  field, Help and Workspace/History.
- B: an actual native XY Viewer. Create a new Session, import `synthetic_xy.csv`
  through the ordinary CSV acquisition owner, and inspect its canonical Variable
  IDs/units. Set desired X/Y units to m/V through normal metadata controls if
  needed. Open the example, choose that Dataset, enter its actual X/Y Variable
  IDs and click Load. Fit/Zoom/Pan use the public retained Curve Source host;
  they do not run an Analysis. Load is an independent handwritten handler.
- C: Workbench-style generic sections, layers, tabs and native scientific slot.
  Its domain callbacks are visibly unbound. It does not clone Curve Workbench's
  CAD algorithms or private controls.

Start all three from the normal Viewers catalog after installation. Use their
Help menu/F1 for installed module documentation. Regenerate into a new output
folder; existing handwritten handler files are preserved. The original input
CSV is an example source; no user Session is bundled.
