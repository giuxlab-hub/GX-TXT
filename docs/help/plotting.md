# Plotting

Plots are derived views of Session data. Graph and Plot Providers declare their available series, axes and interactions. Configure units, ranges, legends and annotations from the Plots page where supported.

Legend placement and entry layout are separate settings. Annotations are non-destructive; saving them records metadata, while exporting or printing creates a rendered result. Rerendering from a module's cache can change presentation without repeating its numerical analysis when that module supports it.

## Combined stabilization controls (dev-051)

Graph Series has a wide Session Dataset chooser, optional manual IDs, lazy cached distinct Family/Second/Filter lists and explicit value refresh. Add/update/remove/reorder touches the relevant series. The common Axes dialog offers Transparent background, 2-D equal aspect and existing 3-D aspect modes. Plots Notes opens the graph's independent Markdown note; Graph Info includes notes/metadata. Variants/Clones carry their own resources. Export/Import Graph ZIP transfers one graph as a new Detached Clone, with a review of integrity/dependencies and an explicit rendered-only choice. See [resource ZIP guide](../guides/PORTABLE_RESOURCE_EXPORT_IMPORT.md).

## Plots toolbar (dev086)

Refresh, Rerender and Open PNG 1:1 remain directly accessible. **Selection** groups
All / None / Toggle / Up / Down; **Render** groups selected/module rerender.
**Presentation** contains Legend, Place legend, Axes, Title and labels, Graphics and
Annotate. **Data / Variants** contains Variants, source-point selection, Select area
and Clear area. **Graph** contains Clone, Edit clone, Delete, Graph info and Notes.
**Import / Export** contains PNG export, annotated export and Graph ZIP import/export.
Menus follow the same capability/enabled state and invoke the original actions.
Graph Series, rendering, shortcuts and Session configuration are unchanged.
