# Session HTML Export

## Purpose

Session HTML Export turns the current GX-TXT Session into a read-only static
website for teaching, supervision, review and archival browsing. It is a
presentation export. It cannot be imported into GX-TXT and is not a substitute
for the portable GX-TXT Session archive.

## Export

Open a Session and choose **Session Tools -> Export Session to HTML...**. Select
an output directory. The module creates `<session-name>-html/` and, by default,
a matching ZIP beside it.

`index.html` is the entry point. Copy/extract the folder on another machine and
open that file directly. No local HTTP server is required.

## Offline operation

All CSS and JavaScript are bundled in the export. There are no CDN, remote
font, remote API or Internet dependencies. The package does not need GX-TXT,
Tcl/Tk, Octave, Python or installed GX-TXT plugins to be browsed.

## Navigation

The site shows only sections supported by actual Session content. It provides
Session overview, Datasets, analyses, graphs, documentation/notes, files and
provenance/export information.

## CSV viewer

CSV Datasets are exported in local JavaScript data chunks. The browser renders
at most 200 rows at once and loads one data chunk at a time. Column headers,
row numbers, paging, per-loaded-chunk sorting and filtering are provided. A
numeric filter may use forms such as `>10`, `<=0.5` or `=3`.

All original CSV bytes remain available from the Files view. No scientific rows
are silently truncated. Sorting/filtering deliberately operates on the current
local chunk so very large files do not require the entire Dataset in browser
memory at once.

## Markdown viewer

Session Markdown is decoded locally and rendered by the bundled GX-TXT
technical Markdown renderer. It supports headings, paragraphs, lists, tables,
fenced code, links and basic inline formatting. Raw HTML is escaped rather than
executed and unsafe link schemes are disabled.

## Graph viewer

Existing PNG, JPEG, WebP and SVG Session artifacts are presented as existing
artifacts; the exporter does not rerun analyses. The viewer provides fit/reset,
zoom in/out, mouse-wheel zoom and click-drag pan, plus access to the original
artifact at full resolution.

## Reports and other files

Normal text/INI/JSON/YAML/log/report-like files receive escaped text views.
Unsupported or binary files are listed with filename/path, size and SHA-256 and
remain available through an original/download link. The exporter does not try
to invent a browser viewer for every file format.

## Provenance

Dataset pages expose available contract, variable schema, units, semantic
roles, producer/source information, Dataset Metadata and notes. The export
information page records source Session identity, GX-TXT version, exporter
version and export timestamp.

## Security

Session names, labels, metadata, notes and filenames are treated as untrusted.
Generated HTML is escaped, Markdown raw HTML is disabled, unsafe URL schemes
are rejected, output filenames are generated from stable hashes and exported
paths are checked against the export root.

## Limitations

- The site is read-only; browser sort/filter/zoom state is not written to the
  GX-TXT Session.
- CSV sorting/filtering is chunk-local by design for scalable `file://` use.
- Browser restrictions prevent programmatic modification of the source Session.
- Unsupported binary scientific formats are downloadable but not interpreted.
- Missing graph artifacts are not regenerated merely for HTML export.

## Graph Notes

Graph Notes API resources are exported as separate note pages linked from graph entries, with graph backlinks. Base, Variant and Clone notes keep their stable associations. RGBA PNG assets and annotation overlays preserve transparency. Portable Dataset/Graph ZIPs are the scientific transfer formats; HTML export remains read-only.
