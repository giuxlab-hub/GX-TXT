# Dataset Preview controls — dev073

Activate a Dataset using the glyph in the right navigator or its Activate menu.
A row highlight only browses the tree. Preview follows the activated Dataset and
catalog notifications automatically. The navigator Refresh icon forces resync of
consultation panes without retargeting an open editor. Variables Help is the last
internal tab. Save Schema remains dedicated to Variables. The navigator Edit icon
opens the existing in-place Metadata, Notes or Temporal Sets editor for the selected
canonical Dataset; Save, Cancel and Back remain inside the editor. Pending sources
must be imported before canonical editing or full Open. Detected CSV structure is
available only for meaningful acquisition/Pending text sources.

Preview's icon group copies readable text, opens canonical Table pages, or clears
the visualization. Copy does not copy embedded PNG pixels. Drag the dotted handle
to move the tools within the viewport. Their location stays fixed while content
scrolls and survives tab changes, Dataset changes and re-render. Table pages is
unavailable for opaque/Pending sources. Clear retains inspection/schema for the
same Dataset. Idle refresh and force resync respect Clear; Render or a new activation
can show visualization again.

Scientific X/Y choices use canonical Variable IDs and preserve declared units.
Filters show only genuine schema-supported Family/Group, Trace/Sweep, Replicate
or text source-kind columns. Buttons show counts of available values and open a
multi-select list (Ctrl/Shift). Filters combine with AND and use exact source values.
Apply the choices, then Render (Preview) or Plot (full CORE viewer).

**Unfiltered XY (one series)** is the default: rows stay in source order, including
legitimate connections across an unfiltered family table. No family is selected
or inferred automatically. Selecting a Family explicitly restricts its rows;
selecting several gives separate member curves. **All members as separate curves**
is an explicit optional action, distinct from All rows (unfiltered). Trace and
Replicate are independent when both exist. Source `kind` is a data classification,
not the Dataset contract or variable dtype. Missing membership hides the controls.
Status names the chosen mode, trace count and retained canonical rows; gaps remain.

Discovery scans at most 100,000 rows in bounded 2,048-row chunks and lists at most
1,024 distinct values per variable. Incomplete scans say sampled/bounded; they never
claim a complete available count or enable All members. Up to 16 family traces
can be drawn at once. Large filtered Transform planning remains synchronous.

3D Preview uses the same CORE Native3D camera and navigation cube as the regular
viewer. The subject is fitted to the actual viewport and geometry bounds. The
smaller cube remains clickable; Zoom +, Zoom − and Fit All sit above it. Left drag
orbits, middle drag pans and wheel zooms. These change the camera, not raster pixels.
The action group stays distinct from cube/zoom tools. The read-only worker closes
on Clear, leaving Preview, Dataset/Session switch or revision change. Full Viewer
presentation defaults and scientific source bytes stay unchanged.

Filter choices first use the persistent CORE Dataset Scientific Profile. Normal
publication/import/replacement/schema commits update it within the existing metadata
transaction. Legacy Datasets without profiles use one bounded read-only discovery
per identity and Session; this cache does not modify metadata or scientific data.
An explicit `datasetScientificProfileBuild` operation can persist the discovered
profile for later processes. Incomplete inventories remain visibly bounded. See
`api/DATASET_SCIENTIFIC_PROFILE_API_v1.md` for exact identities, bounds and limits.

The embedded Preview's Auto backend uses the existing Mesa Software policy for
consistent compact-cube colors on this server. Explicit backend choices are
respected; the full Viewer retains its original backend and presentation.

The profile avoids repeated categorical-inventory scans. Rendering an XY plot still
reads its requested scientific rows through the existing Curve Source facilities.

Legacy Single-file input has its existing authority exposed through a navigator glyph
when an input file is configured. Use detected CSV structure is shown only for the
legacy single-input importer; generic Pending sources already detect structure automatically.


## Dataset coordinate settings

**Dataset coordinates…** opens the shared editor for the active canonical Dataset.
Choose compatible display units independently from persistent view magnification
and from numerical calibration. Preview renders canonical values in the chosen
display units and applies the saved view factor around the source-coordinate pivot.
Its text reports the applied units/factors and states that numerical calibration
is not applied. Changing these settings invalidates the existing Preview cache.

The full scientific Dataset viewer reuses the same settings. Reopening or pressing
Fit applies the factor once from the full fitted range. Transient pan/zoom remains
separate. A live policy edit refreshes retained samples from their canonical copy;
it never scales previously displayed values again. Source rows and canonical
Table pages remain unchanged. Overlays with different coordinate policies are
rejected with an explicit explanation; select compatible policies or inspect them
separately. Source selector units and displayed axis units are labelled separately.
