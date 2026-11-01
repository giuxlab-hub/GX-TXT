# Scientific Library Workspace

Scientific Libraries consults the existing CORE Scientific Library Manager. It lists registered managed, external and remote libraries, searches individual provider entries, shows exact public metadata, provenance and capabilities, and delegates scientific viewing to the specialized Viewer.

## Open the common Libraries workspace

Open Configuration, choose Libraries, and use Open Libraries… . The Scientific Libraries tile under Scientific Data & Mathematics opens the same Viewer. CORE Scientific Library Manager remains the sole registry, integrity, registration and provider-dispatch authority. The shared CORE catalog owns lists, status, request lifetime and capability-driven actions. The legacy Scientific Reference Library and Scientific Library Manager are deprecated: their saved Viewer routes remain available, while normal catalog navigation uses this one management tile. Specialized IR/NMR Viewers remain distinct scientific consumers.

## Browse registered libraries

Choose Storage mode to show all registrations or one mode. Type a fragment of the library name, ID, type, origin or provider in Filter registered records and commit it with Enter or by leaving the field. A filter change returns to Page1. Each page contains at most100 matching registered libraries; Page selects another page without changing library identity.

Library type selects an exact installed provider type. Mode, text and type filters apply together before pagination. Type providers lists the installed providers' actual declarations and registration schema, including providers without an installed library. Unknown types fail explicitly.

Select a library in the left list. The right tabs separate Library information, Capabilities, Entries, and Activity and diagnostics. Library information distinguishes raw registry.* fields from effective status.* observations. The Capabilities table distinguishes declarations from actual enabled operations and gives unavailable-state reasons. Both information tables provide horizontal and vertical scrollbars for long values, reasons and additional rows. Select a visible row and use Ctrl+C to copy its complete tab-separated cells; copied rows are separated by newlines. Refresh reloads the original registry; it does not turn a remote registration into a local copy.

Unknown information is not zero. In particular, old external/remote registration defaults do not establish that the remote source has no entries or needs no authentication. Unavailable, unsupported mode, missing provider and authentication-required states must be read as reported; successful registration alone does not establish connectivity.

## Open a scientific library or entry

Open library uses the provider's actual registered Viewer. The existing IR provider opens its Scientific Spectral Library. The existing NMR provider has an entry Viewer, so its established library-open route opens the first real managed entry. To choose a specific reference, select its ID on Entries and use Open entry. Original library and entry IDs remain with CORE and the domain Viewer.

On Entries, type a query and press Search entries. This queries individual entry IDs and provider-defined metadata through the public normalized search operation; it does not filter library names. Empty search lists provider entries. Each page contains at most100 entries. Next entries and Previous entries retain the exact original query and provider continuation identity. Editing a query takes effect when Search entries is requested. A changed source can invalidate an old continuation; the error is shown rather than reported as an empty successful page.

Select one entry to inspect its exact metadata, source revision, content contract and provenance in the lower table. Hashes are displayed only when actually supplied by the provider. The result_json row retains authoritative JSON types and complete nested information; copy a selected table row with Ctrl+C. Missing search/info hooks, access policy, locked credentials and unavailable sources produce an explicit error. A successful empty page means the provider returned no matches. Existing IR comparison/ranking and NMR chemical-shift/nucleus presentation remain in the specialized Viewers.

## Capabilities and provider actions

Controls are enabled from the selected provider's actual capabilities, storage mode, availability, authentication state and library policy. A provider may declare extra management actions; select one under Catalog navigation and use Run provider action. Unsupported or currently unavailable actions remain disabled. The diagnostic tab retains the last actual action result or error with the original library identity while registry and capability information refreshes. A submitted or cancelled request is distinct from an operation that actually completed.

Read only describes scientific entry policy. It does not prohibit authorized managed package updates/removal or unregistering a reference. Catalog administration uses the existing Library Manager. The integrated typed-record pages use its same entry transactions; this Viewer adds no numerical engine, renderer or private library store.

## Library administration

Install managed package selects a genuine Scientific Library ZIP for the existing CORE validator and installer. Verify rechecks actual managed payload/package integrity and the provider's entry index. Update requires an appropriate newer same-ID package preserving stable entries. Remove managed library confirms removal through the same manager; saved references can become stale.

Register external library and Register remote library use shared CORE forms. First choose a real installed provider type, then enter a unique stable ID, readable name and actual source/license/rights information plus the provider's declared non-secret configuration. Registration does not copy an external source or mirror a remote service. A provider that does not support that mode is explicitly registration-only. Never put passwords, tokens or API keys into configuration fields.

Unregister selected library removes only an external/remote registration and retains the manager's tombstone identity. Managed libraries use Remove instead. Cancel a chooser or confirmation to abandon that request. Cancellation is not rollback of an administrative operation that has already committed. Wait for actual operation completion before issuing another administrative action.

## Lifetime, Help and current scope

Registry access itself needs no scientific Session. A Viewer captured in a Session can become stale when that Session changes; close and reopen it to obtain a current owned window. Reopening even at the same window path starts a distinct catalog lifetime. A late or duplicate reply from an earlier Session, request or closed window cannot clear the current request, consume its pending refresh, or replace its action receipt. Closing cancels the window’s owned asynchronous information requests through the existing Script Job transport. This does not roll back an administrative operation that already committed. Refresh and selection do not publish a Dataset, and reopening does not promise restoration of the earlier selection or pending operation.

Use the normal Help menu, F1, or Help control to open this module manual in the CORE Documentation Browser. The three-book icon represents library consultation and management; it is an original project SVG imported and packaged through the existing CORE icon catalog, licensed GPL-3.0-or-later.

The catalog retains consultation and authorized whole-library management. Records, Sources and Manual entry are additional pages in this same Viewer. Every provider exposes its actual supported operations; registration alone does not establish remote access. Scientific Libraries remain independent of Sessions.


## P028 typed records, remote sources and offline technical files

Use **Records**, **Sources** and **Manual entry** in the existing Scientific
Libraries Viewer toolbar or page selector. These are in-window pages, alongside
Library information, Capabilities, Entries, Activity and diagnostics, and Type
providers. The original Library catalog and administration controls remain
available in the left inspector. This generic Browser uses installed domain field
and relationship declarations; future compatible domains/connectors need no
Viewer source edits. The Records page searches across installed typed Libraries
with exact type filters and pages of100. Select a record for typed fields,
provenance, actual images/documents and incoming/outgoing source assertions.
Follow a resolved exact Library link or use Back/Forward. Stale/missing/external targets
retain source evidence and never silently retarget or import content.

Sources lists normal registered source Libraries. Register an installed
connector, enter a query and choose **Look up (read only)**. Resolve ambiguity by
selecting one exact source result, then preview. Select any subset of available
records and explicitly **Import selected into persistent Libraries** with a
Library ID prefix. This action saves persistent Libraries without a Session.
Actual selected linked files can be downloaded; unavailable files remain external
references. Source-suggested alternatives are OFF by default: enable the option,
preview an actual selected suggestion and select its independent records before
saving. Supplier classes are source claims, never validated drop-in equivalence.
Batches spanning Libraries report separate completed/partial/failed commits.
Cancel requests cancellation; already committed Library versions remain saved.

**Manual entry** works without network or supplier accounts. Drafts remain intact
when moving between Viewer pages; normal close asks before discarding a changed
draft. Cancel draft explicitly resets the unsaved form without changing Libraries.
Choose a declared record schema, enter its source identity and typed fields,
paste source specifications as name TAB value or name: value when that schema
supports it, and select already-downloaded PDF/photos/drawings with their roles.
Domain-declared component templates provide identity fields and editable technical tables with Add/Edit/Remove, original values, numeric values/units and test conditions. No JSON is required for component fields. The entire manual form scrolls on small windows and larger fonts. Preview opens a structured review with Save/Cancel; Save preserves
source text, original file bytes and SHA in the persistent Library. Edit selected
record makes an immutable new revision with the previous content pin/history.
A footprint illustration remains an image; no native EDA footprint or SPICE
model is inferred. Images open in the same Browser from exact stored bytes.
PDF documents open inside the same Viewer page using the existing shared
PDF reader. Use Back to page to return to the retained record or draft. The same action previews an unsaved local PDF or an immutable saved
Library resource, without requiring a Session or creating a Dataset. Use the
reader's Previous/Next page, Fit page/Fit width and Zoom controls. Original bytes
and SHA remain exact; draft viewing copies at most32MiB into an existing managed
viewer resource and never changes the user's file. Closing the PDF or Viewer
retires its reader process group before releasing that resource, including after
forced parent-window destruction. Open original copy externally
is an optional secondary action.

Offline candidates are optional and Include defaults off. Paste schema-column TSV,
parse, inspect a row with Return, and check only the actual candidates you want.
The selected-record review shows full identity, source attribution and pinned
Entry/revision/SHA. Cancel saves no records. Explicit Save creates independent
entries and attributed directed suggestions; compatibility remains unverified.
A suggestion kind must be declared by the installed domain provider.

Later, independently, use **Import selected records…** for highlighted left-list
rows, or **Import displayed record…** for the exact record currently shown after
Follow/Back/Forward. The displayed Library/Entry/revision/SHA identity is visible
above its details. On Related, **Import selected related entries…** reviews only
your bounded checked/highlighted subset, resolving the other end of incoming or
outgoing links. Stale, missing, external and Dataset links are not implicitly
imported. Each distinct pinned Library entry is reviewed once.
 Review each actual representation, compatible installed Acquisition
Handler, proposed Dataset ID, target Session and Namespace. The existing
Acquisition API owns RAW, SHA and canonical Dataset admission. Component and
publication metadata have their own domain handlers; real PDF/image/SDF resources
use existing handlers. No Dataset is created by lookup, preview or Library save.

Credentials opens the existing protected Library credential profile UI. Keys
never belong in Module Configuration. Source authorization errors affect that
connector; ordinary offline Libraries remain usable. The new Configuration >
Modules > Library Importers tab immediately precedes Export and lists actual
source connector declarations. The existing Acquisition page retains its scope.

The existing Molecule Viewer consults a pinned Library structure read-only,
without creating a Dataset. It exposes the original geometry/projection and an
embedded existing Native3D viewport, including with no Session open. **Open 3D
structure** uses the exact source conformer and the existing molecular mesh
helper inside a managed Resource allocation; CORE validates the derived mesh SHA
separately from the original source SHA and Entry revision. Orbit, pan, zoom,
Fit/Reset, native geometry selection and both molecular styles use that same
renderer. Source coordinates, conformer identity and original bytes remain exact;
close releases the viewport, worker and staged resources. This requires P028
NATIVE_3D_GUI_HOST_API_v2 managed_artifact capability. No fake Session, saved
scene or automatic acquisition is involved.


The Mouser official Search API is a read-through source: inspect actual typed
fields, media, documents and supplier suggestions without saving its API content.
Double-click a source record or choose **Inspect source record…**. Source image viewing uses transient memory; document links open only
on explicit action. Persistent import is disabled only for that channel under
its current published source conditions and the owner's confirmed requirement.
The independent manual form still saves user records/files offline without a
supplier account. Its manufacturer, MPN and supplier SKU fields remain distinct;
General, Power connector, Capacitor and Memory IC templates are provider data.
Original pasted text, editable technical rows, local photos/PDF/drawings, source
identity, exact original bytes and SHA are retained. The review's Cancel writes
nothing; explicit edits preserve immutable prior versions. **Last receipt** on Records reports per-Library/per-Acquisition outcomes without hiding partial work.

Actual numeric scientific spectra can use the separate Scientific Spectra
Library/domain packages and Scientific Spectrum CSV and JCAMP Acquisition module.
CSV axes, units, technique and representation are explicit source metadata or
ordinary importer configuration; supported JCAMP headers provide their declared
semantics. The existing CORE parser performs scientific validation. A source
annotation or spectrum picture is still only its actual reference/image, never a
new trace. Import review lists only installed handlers with both declared format
capabilities and an actual recognized inspection result.

JPEG and PNG source pictures are decoded through the configured ImageMagick
media owner into a bounded display raster in memory. Original and preview SHA
identities remain distinct. Source pictures and derivatives are not cached to
disk. Cancel and close release the managed request. Unavailable codecs or
oversized/malformed pictures report a bounded preview error; ordinary technical
fields and document links remain consultable. Local user-selected JPEG files
use the existing media preview owner and managed disposable resources while
retaining the original file and its exact SHA.


## In-window consultation and keyboard use

Image, PDF, source detail, candidate inspection, structured review and operation
receipt views remain inside their originating Viewer page. **Back to page**
returns to the retained selection or manual draft. Use **Show local image thumbnails** to load up to four
actual local image previews through the bounded shared media owner. Click a
thumbnail for its original image; Fit image and Original pixels retain scrollbars. PDF controls belong to the existing reader.
Normal file choosers, typed specification-row dialogs, confirmations and separate
specialized scientific Viewers retain their original roles.

Records and Sources have a shared vertical form scrollbar; their result tables
also retain horizontal/vertical scrollbars for full original values. The Manual
form scrolls with focus and wheel. Tab/Shift+Tab follows native controls; Return
submits a query or inspects a selected candidate, and Space toggles that candidate.
The shared Viewer page selector exposes overflowed tabs on narrow windows.

## Editable Builder source and compiled identity

The installed module includes source/project.json, source/design.gxtxt-viewer and
source/handlers.cpp. Copy that source project to an ordinary user-owned development
folder and open it with the existing Viewer Development Workspace/Interface
Builder. The three declared library_browser components share one group and use
the existing CORE Library services. The genuine C++ handler emits the original
catalog intents and the finite browse_records/browse_sources/browse_manual
presentation intents. Build and export use the ordinary restricted compiler and
package owner; no runtime compilation or scientific storage is added.

## Scoped Library views in other Builder interfaces

Any compatible Viewer may declare the same three Library Browser pages with a
shared group and optional typed `scope`. Available axes are Library types,
record types, registered Library IDs, actual domain-provider IDs and exact source
IDs. OR applies within each axis; axes combine with AND. The scope is displayed
on every page, and applies before record counts/paging, source choices, typed
source previews, manual templates and navigation. An unavailable selection stays
empty and explains its status. Absent or empty scope retains this Workspace's
normal unfiltered behavior. This is a presentation filter, not an access grant.

Related rows show exact other-end Library/entry/revision/content identity and
retain outside-scope assertions. Opening such content requires an eligible
explicitly resolved reference. Canonical Dataset links use the existing Dataset
Viewer only when the exact current Session and payload SHA match; otherwise open
the matching Session normally or explicitly repin an old ambiguous reference.
Acquisition review shows full entry pins and selected representation SHA,
contract and handler. Final Session/Namespace review retains every reviewed
selection and its independent per-entry outcome semantics.
