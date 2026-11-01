# Sketch, PDF and local Spline workflows — dev-070

## Select and convert

In the default Local Geometry Selection mode, click one Spline span, even inside a
Path assembled from other Paths. Only that span highlights. Ctrl adds and Shift
subtracts. Defining controls retain hit priority. Right-click the existing Select
button for Entire Curve / Path; list Select and graphical window selection still
select complete logical objects.

Choose Modify → Convert Selected Spline Segment to Line. This replaces precisely
one curved span, preserves the exact adjacent curves and endpoints, and creates one
Undo/Redo transaction. Incompatible constraints or dependent parameter fragments
produce a non-modal explanation without changing the original geometry.

## Publish and open Sketches

Use Workspace → Publish / Export as Sketch Dataset. With no geometric selection,
all eligible curves are exported. With selection, only the selected semantic
geometry is exported, including individual Spline spans and Line segments. Choose a
new Dataset ID and Apply; the shared form stays open until Close. The Workbench
status lists the exported entities and any scientific-to-geometric conversions.

Scientific XY curves become retained point/Polyline geometry using their exact
coordinates, declared units and gaps. Their source Datasets and Workspace bindings
remain unchanged. No analytical Spline is inferred. Exact retained objects keep
primitive families, transforms, topology, constraints and named parameters. Include
all geometry referenced by a constraint, or resolve the reported subset dependency.

Select the Dataset's activation glyph in Dataset navigation, then Dataset Preview.
A geometric preview appears through the normal preview infrastructure. Open Dataset
opens an editable Workbench draft. The Sketch needs no original scientific sources.
Portable `.gxsketch` files can also be imported with Sketch Dataset Import.

Workspace Save saves the draft. Workspace → Commit changes to opened Sketch Dataset
explicitly updates the canonical Dataset. A concurrent canonical revision change
rejects a stale commit: reopen the current Dataset before trying again. Ordinary
Save never publishes a new Dataset. A foreign producer must explicitly authorize
this specific Dataset revision through CORE before Workbench can commit it. A
successful revision change consumes that grant. Other foreign Datasets remain protected.

## PDF export and reading

Workspace → Export Current View as PDF preserves the current framing.
Workspace → Export Entire Workspace as PDF fits all graphical content, including
geometry outside the current view. Both create standard `document.pdf` Datasets.
They render the canvas graphics, scientific curves, grid, coordinate indications,
visible dimensions and constraints; application panels are excluded. Native's shared
presentation renderer supplies vector paths/text and any reference-image layers.
Light canvas colors are darkened on white paper for readability. View and geometry
are restored after export.

Select an imported or generated PDF in the normal Dataset browser and press Open
Dataset in Dataset Preview. The integrated reader provides Previous/Next, Zoom −/+, 
Fit page, Fit width, scrollbars, wheel zoom and left/middle drag Pan. Its title shows
the Dataset ID and its toolbar shows page/total. Ordinary reading does not start OCR
or require enabling the optional specialized viewer. PDF/OCR uses the same shared
canvas and Poppler rendering infrastructure and keeps its existing operations.

Supported Debian dependencies: configured Python with Tk and Pillow, Poppler
`pdfinfo` and `pdftoppm`; PDF creation also uses ReportLab. DejaVu Sans is used for
Unicode PDF text when installed (Helvetica fallback). The supported server has all
of these. Missing reader dependencies are diagnosed before launch; malformed PDFs
show a reader error. PDF consultation never writes the Dataset.

## Navigate while editing

Hold the middle mouse button and drag to Pan, then release. The wheel still zooms.
This works during Select and unfinished construction without moving geometry,
changing selection, adding Undo entries, or committing/cancelling the active tool.
