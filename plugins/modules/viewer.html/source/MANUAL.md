# HTML Dataset Viewer 1.2.3

This Viewer consults canonical HTML Datasets from the current GX-TXT Session.
The shared CORE document owner presents interactive HTML through the installed
precompiled native HTML runtime. Authored Viewer code uses the existing typed
`document_bind` operation; it does not read arbitrary files, implement a browser,
compile code at runtime, publish Datasets or create scientific results.

## Open a canonical document

Open **HTML** from the Viewers catalog. Select a compatible source in **HTML
Dataset** and choose **Open HTML Dataset**. The normal Open Dataset workflow uses
the same Viewer. With no Session or compatible HTML source, the document area
provides the corresponding selection guidance. An incompatible or stale source
is unavailable; it is not silently relabelled or replaced by another Dataset.

The canonical Dataset ID, revision and SHA remain authoritative. Reading,
selection, navigation, page interaction and zoom do not save to or rewrite the
canonical source. Changing Session or replacing a source requires explicit
selection/reopening. A changed or unavailable native presentation is reported as
such; the interactive surface does not fall back to inert text while claiming
that scripts or CSS ran.

## Shared interactive presentation

The isolated native surface enables ordinary HTML layout, CSS, JavaScript, DOM,
SVG and canvas. Page forms and inputs affect the presented page; they provide no
GX-TXT publication, Tcl, process or Script Bridge capability. The native profile
is temporary and ordinary file access, uploads/downloads, privileged permissions,
popups and unrestricted network requests are denied. This is not an assertion of
absolute protection against hostile native code or every browser vulnerability.

A canonical standalone HTML Dataset supplies only its exact HTML bytes, copied
through CORE Resource Management into its own presentation allocation. Inline
CSS/JavaScript can work within that document; paths next to the Session source
are not thereby authorized. Indexed documentation packages use their separately
admitted package root for confined relative web assets. Do not infer that an
arbitrary HTML Dataset is a web-asset bundle.

Use the native document's ordinary selection and Copy workflow to copy readable
content. Pointer focus, Tab traversal, scrolling and selection belong to the
embedded native surface. These workflows still require actual integrated GUI
verification for the current build; old inert-reader results are not evidence
of native browser behavior.

## Navigation and zoom controls

The shared document component has a navigation row with **Back**, **Forward**,
**Home**, **Reload** and **Stop**, and a separate **Zoom** row with **Smaller**,
a percentage choice, **Larger** and **Reset**. Zoom is bounded to **50–300%** in
**25 percentage-point** steps; Reset requests **100%**. Controls wait for matching
native request completion. A selected percentage is a request; the displayed
percentage is the current observed native value. Unrelated resize or visibility
notifications cannot stand in for the matching zoom completion. Closing,
rebinding or source failure discards the old control request and native lifetime.

Zoom affects the local native presentation, not canonical HTML bytes or global
GX-TXT fonts. Actual narrow-window layout, native button input and close/reopen
behavior remain integrated GUI verification items. Ctrl+plus/Ctrl+equal,
Ctrl+minus and Ctrl+0 were explicit shortcuts in the former inert text reader;
this release manual does not assert that they work in the new native surface
before the current focus/keyboard behavior is observed. No native keyboard
handler or focus repair is introduced by this footer/manual update.

## Preserved inert public render operation

`HTML_VIEWER_API_v1.render source` remains the existing headless native run-model
operation. It interprets supported headings, paragraphs, lists, simple tables,
code and styled inert links; JavaScript, forms, CSS and external resources remain
inactive in that legacy operation, and images may be omitted. Its original
`apiInfo` inactive fields describe that operation. They do not describe the
separate shared interactive host selected by the document component.

The host-only attach/load/navigation/inspect/detach methods retain the existing
public HTML owner. They do not grant arbitrary HTML execution through Script or
restricted author APIs. Consult the current public owner documentation for exact
source admission, state and lifetime receipts.

## Media, platform and acceptance limits

General remote browsing and arbitrary network access are unsupported. Intentional
external HTTP(S) navigation uses the existing safe opener subject to current
native-input policy. A bounded experimental YouTube media policy is not proof of
playback: client identification, permitted service requests, codecs and actual
video playback remain **unverified**. No Referer spoofing, media acceptance or
YouTube compatibility is claimed by this package.

The current prebuilt HTML host is staged for the reviewed Debian x86_64/Qt6
WebEngine environment. Other platforms or missing/mismatched runtime dependencies
must report unavailability until a supported matching prebuilt is supplied.

Version1.2.3 changes the authored explanatory footer, version and this manual
through the official Development Workspace/Builder owners. It preserves the
C++ handlers, declared public capabilities and canonical source binding. Source,
validation, developer Build and standard export receipts qualify that authoring
work only. Native embedding/rendering, focus/keyboard, copy, layout/navigation,
media, responsiveness, installation and final integrated acceptance are separate
MAIN-owned checks. Historical 1.2 inert-reader GUI receipts remain preserved and
are not relabelled as acceptance of this shared browser host.
