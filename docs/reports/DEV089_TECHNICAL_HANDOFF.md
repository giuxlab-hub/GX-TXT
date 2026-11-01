# GX-TXT 0.9.8.10-dev-089 — corrective technical handoff

Status: six implemented corrections verified by focused real GUI workflows.
Installation receipt is appended to the external handoff after publication.
Manual acceptance is PENDING. This release stops at that boundary.

## Baseline and scope

The complete `GXTXT_DEV088_NEXT_CORRECTIONS.md`, workspace script catalog and
permanent development rules were read before implementation. The verified
published dev088 archive, expanded directory and installed source matched 5412
files. Baseline archive SHA-256:
`1a20a0b4548cd3399719c8466994858fc7774692cabc67a1a3b82cb7a7b3b598`.
The work is a new incremental dev089; dev088 history is not overwritten.
All 101 installed module package trees are byte-identical to dev088. The actual
Acquisition inventory is 16, not the 154 historical external-plugin packages.
No external plugin or Session Generator package changed.

## BUG-001 — demonstrated cause, selective rows and correction

**The demonstrated defect is incomplete native popup repaint after X11 mapping
on the existing Windows multiwindow X server.** Tcl/Tk has the correct strings
and correct rendered text in its XComposite redirected popup pixmap, while the
corresponding Win32 popup client surface displays a stale opaque rectangle.
Reissuing damage for the complete popup rectangle restores those exact pixels.
This is a presentation/invalidation failure in the existing direct-network
VcXsrv path, not empty values, white text, disabled items, a variable-ID error,
a Tcl/Tk theme defect, or SSH X11 forwarding.

The investigation followed the requested order:

1. Normal Debian desktop first: the real existing Xorg display `:1`, normal GDM
   Xauthority and XFCE desktop. Baseline dev088 Type/Core/Group, Acquisition
   importer and Dataset selectors were readable, before and after native
   rendering. The original 540-row curve and 1681-row surface were tested using
   private copies. No local Xvfb simulation was substituted for this test.
2. Only after local reproduction failed, use the existing direct TCP X display
   `192.168.1.111:0`. Server vendor is `X11R0 HC-Consult 210116001`; its existing
   process is VcXsrv in multiwindow mode. No remote session, SSH forwarding,
   driver, authentication, desktop or X-server setting was changed.
3. Compare working and failing controls, individual rows, actual Tcl widget
   configuration and the listbox. The failing Modules Type list contains
   `All`, `Acquisition`, `Analysis`, `Measurement automation`. Listbox state is
   normal, foreground `#000000`, background white, selected foreground black,
   selected background `#c3c3c3`, font `TkTextFont` / DejaVu Sans 10. Every row has
   a valid nonempty text bbox; per-item configuration does not hide any row.
   Values/configuration/style/state records are preserved with screenshots.
4. Capture actual Windows screen pixels of the uniquely titled private GUI.
   X11 `import` and root captures alone initially looked correct and were not
   treated as remote acceptance. At the same failing state the named XComposite
   popup pixmap contains every label, while the native Windows popup is blank.
   Root stacking inspection places the popup above the application. Moving
   the same popup changes which screen region is affected without changing
   any value, font, color or selection metadata.
5. A native full repaint of the exact private popup HWND restores all four
   labels, without modifying Tk state. A focused `XDamageAdd` of the measured
   root-space popup rectangle has the same effect. The decisive diagnostic
   pair is `remote-final/xdamage-before2.png` / `xdamage-after2.png`; its measured
   region was `[304,118,161,76]`. The separate native repaint pair is
   `remote-diagnostic/damage-before.png` / `damage-after.png`.
6. Timing matters: a map-idle-only notification and a 25 ms notification could
   still leave the 540-row curve popup's upper rows invisible while its final
   `point_index` row stayed visible. That mixed failure was reproduced in the
   real Windows capture, rather than inferred from the original screenshot.
   A single complete-region notification at 150 ms after map passed the
   Type/Core/Group, curve X/Y/Z, surface X/Y/Z and Print matrix. Native choice
   actions still operate on the existing popup and stable schema IDs.

**Why only some dropdowns/entries?** The stale area is a screen-space rectangle,
not a set of names or data values. Rows intersecting that area are visually
covered; rows outside it are readable. A different popup position/size or a
later full native paint changes the affected intersection. This accounts for
all-blank Type, mixed curve rows and readable controls in the same process.
The current selection and invisible rows remain present and selectable because
Tk's listbox data and input handling are intact.

The upstream source corroborates the transport mechanism: VcXsrv redirects root
subwindows through XComposite, mirrors root-shadow damage into Win32 invalidation,
and its native paint path copies the redirected window pixmap. See the primary
[shadow damage implementation](https://github.com/marchaesen/vcxsrv/blob/master/xorg-server/hw/xwin/winshadgdi.c)
and [multiwindow mapping implementation](https://github.com/marchaesen/vcxsrv/blob/master/xorg-server/hw/xwin/winmultiwindowwm.c).
The experiment proves the missing/stale native presentation and the corrective
complete-region damage notification. It does **not** establish which earlier
user action initially triggered it, or assign blame to a specific upstream
source line without an instrumented upstream trace.

**Correction:** the existing shared GUI owner installs an additive Tk
`ComboboxPopdown <Map>` binding only for the demonstrated HC-Consult X11 server.
One bounded post-map callback calls the small CORE X11 host transport. It uses
Tk's existing Display and mapped popup bounds, creates a temporary XFixes region,
issues `XDamageAdd` for that complete root-space rectangle, frees the region and
synchronizes the request. It checks XDamage 1.1 and mapped popup identity.
It changes no popup pixels, values, colors, fonts, theme, styles, state, layout,
WM override-redirect semantics or scientific metadata. Local Xorg retains Tk's
standard path. No periodic redraw loop or extra X11 connection is introduced.
This supplies the omitted presentation damage; it is a narrowly scoped platform
compatibility repair, not an upstream VcXsrv binary patch or a cosmetic text fix.

**User clarification preserved:** no reliable original action sequence is known;
immediate-after-launch status was not confirmed. The earlier documentation
navigator rectangle disappearing after a canvas click is an additional historical
observation. Its equivalence and trigger remain unproven and were not claimed
fixed by this combobox-specific release. No correlation with 3D, imports or fonts
was assumed. Fresh backing-store captures alone had initially suggested success;
actual native captures subsequently reproduced the defect.

## BUG-002 — canonical names and stable IDs

The old combobox used technical Variable IDs directly as display values, while
its adjacent report already resolved canonical names and units. The actual
scientific preview owner now projects canonical name, optional unit and
supplemental ID through the existing public `datasetVariableById` association.
Selection resolves against the current eligible public schema and Dataset/Session
token; the existing numeric `previewMap,x/y/z` fields remain stable IDs.
No `v000N` suffix parsing, raw-position inference or persistent parallel map was
added. Session/Dataset changes regenerate the projection. Ambiguous default axes
remain unselected until chosen; existing transient choices do not create new
Session preference persistence.

Real GUI tests cover all three surface selectors and a deliberately shuffled
16-point mixed-type schema: `v0003` is canonical position 1 (temperature K), a
text category is position 2, `v0001` is position 3 (radial mm), and `v0002` is
position 4 (axial mm). Native choices select the correct stable IDs and render
all expected points. The text category remains valid scientific metadata but is
excluded from numerical axis choices. The reported 540-row curve retains names,
units, filtering semantics and compatible XY rendering.

## BUG-003 — honest camera orientation

The old colored symbol was a **world-origin axes gizmo**, not a camera widget or
interaction pivot. The data's temperature coordinate is around 300 K; origin
(0,0,0) lies far below the cloud and its projected triad was nearly clipped.
Moving the data or changing camera bounds would falsify that relationship.

The shared modern Native3D view now has an additive size-tagged screen-space
orientation API. A separate transparent renderer layer owns a centered VTK axes
actor and a small parallel camera that follows source camera direction/up/roll.
It anchors to a padded viewport corner independent of world origin, pan/zoom,
scientific units and geometry. Defaults are off; numerical XYZ enables it and
disables its old world-origin axes. Modern scientific Plots keeps calibrated
axes/colorbar. Existing C ABI structures/signatures are unchanged; packaged
Debian engine and Tcl transport were rebuilt together.

Tests use the original 1681 points and a second 16-point numerical Dataset at
1280×840 and 920×650. Native orbit, roll, middle-button pan, wheel zoom, resize,
reset, tab return and Exit pass. One worker/scene is reused. Orientation crop
pixel differences after left/up/roll are 618/665/707; reset differs by zero pixels.
Source hashes and point counts remain unchanged. Exit restores retained 2D.
The modern Thermal Plots preview still displays calibrated mm/K axes and colorbar.

## BUG-004 — final notebook owner

A final notebook reorder in `app/storage_identity_gui.tcl` still placed Print
before Projects, overriding earlier creation order. The actual final list is now:
`Acquisition | Dataset | Analysis | Run | Results | Plots | Sessions | Projects |
Print / PDF | Modules | Viewers | Configuration | Help`.
Stable widget/page IDs and controllers are unchanged. A fresh GUI verifies all
13 pages; Projects opens and Print paper/orientation controls still operate.

## BUG-005 — category-wide effective ALWAYS

The old gate equated acquisition's selectable metadata/enable flags with Analysis
membership. CORE represented ownership, and did not guarantee activation; hence
CORE / OFF and external ACTIVE/inactive states. `moduleIsAlwaysAvailable` now
derives ALWAYS from `kind=acquisition` or the pre-existing `selectable=0` policy.
Both effective query and owning enable-set implementation use it. Modules lists
all Acquisition entries, including previously hidden non-selectable providers,
and renders CORE / ALWAYS or ALWAYS without promoting external packages to CORE.
Help and state actions use the same policy. Analysis flags remain selectable.

All 16 descriptors, versions, ownership, dependencies and runtime handler loads
are inventoried before/after. All handlers load; generic CSV uses its existing
built-in path. `acq.xas` retains `math.numeric`; `acq.crystal_density` retains
`viewer.crystal_structure`. Descriptor/package bytes are unchanged. This proves
registration and invocation availability, not every supported format/device/codec.
Missing external prerequisites and malformed files still report their existing
errors. Native imports cover formerly CORE / OFF WAV plus external Touchstone
and molecule providers; CSV folder import and normal Session publication pass.
The old default-state matrix and the user's screenshot states are distinguished;
user-specific saved flags can differ from a fresh default inventory.

## BUG-006 — categorized browser and usable queue

The actual Acquisition GUI builder now places a tree on the right with groups
from authoritative Module metadata and names keyed by stable module IDs. Existing
custom Importer Builder definitions appear under Custom importers. Search uses
name, ID, group and description; expansion/collapse, scrolling and a count are
available. General Builder/Contracts/Refresh tools sit above it with text/tooltips.

The left side shows selected provider name, description, stable identity/ALWAYS,
workflow instructions and the existing provider configuration. Pending sources
use compact cards with source, Dataset ID/contract, delimiter/header where
applicable, Include/Preview/Variables/Remove/status and import/source-storage
controls. Existing callback/widget paths, provider dispatch, canonical publication
and successful-row pruning are retained. Variables opens the actual Variables
subtab, even after reviewing Preview. No importer engine was duplicated.

Real GUI iteration exposed and corrected sibling-widget stacking in the new card
containers and toolbar wrapping after construction. The final ordinary workflow
chooses categories and a custom definition, searches, collapses/expands, selects
options, adds both CSVs through the native folder dialog, reviews pending Preview
and Variables, imports, inspects canonical rows and reopens the Session. Single
native file dialogs/imports also cover WAV, Touchstone and molecular structure.
At minimum size the browser remains right and all queue actions remain reachable
through the existing scroll area; no horizontal giant table is required.

## Real tests and evidence

Root evidence: `_evidence_corrections_dev089`. Original four PNGs/README/hash/ZIP
remain byte-for-byte in `../compito/GXTXT_DEV088_GUI_EVIDENCE`; a preserved intake
copy is included in the release evidence. Other referenced original BUG-002–005
screenshots were not deposited, so agent-captured dev088 baseline screenshots
provide those before views; they are identified as such.

| Check | Result / evidence |
|---|---|
| Local baseline popup/configuration matrix | PASS: `local-before` |
| Native remote defect and exact pixmap comparison | PROVEN: `remote-before`, `remote-diagnostic`, `remote-final` |
| Post-map complete-region correction matrix | PASS native pixels: `remote-complete` Type/Core/Group, curve/surface X/Y/Z, Print |
| Fresh final GUI, 13 pages, browser/custom/search, Analysis toggle, CSV workflow | PASS: `gui-final.log`, `UI_IMPORT_PASS` |
| WAV/Touchstone/molecule publication, provenance and reopen | PASS: `ACQUISITION_IMPORTS_PASS` |
| Shuffled mixed schema / 16 XYZ points | PASS: `NUMERICAL_PREVIEW_PASS fixture` |
| Original surface / 1681 XYZ points and camera/resize/2D | PASS: `NUMERICAL_PREVIEW_PASS surface` |
| Modern Thermal calibrated axes/colorbar | PASS: `PLOTS_REGRESSION_PASS` |
| All 101 package bytes, 16 runtime handlers, consumer/rename inventory | PASS: `audit-final` |
| Final installed process and native remote smoke | Appended external publication receipt |

The final log retains one corrected test-harness assumption: legacy Touchstone's
optional schema extent is unknown, so extent was verified using the authoritative
read API instead. It returns exactly three frequency samples (1/2/3 MHz → Hz).
An attempted historical dev087 Plots helper used a stale button path; successful
regression uses dev088's current image-host icon via the new runner. Earlier
layout/diagnostic trials remain distinguishable from final acceptance. No long
scientific campaign or unrelated development was run.

## Owners, consumer inventories and rename discipline

No Tcl rename or alias layer was added. Actual owning implementations were edited;
additive GUI/native helpers are loaded directly. The unchanged existing predecessor
chains are inventoried in `audit-final/consumer-inventory.json`: 101 installed
modules, 2128 source files across current CORE/GUI/bridge/viewers/tests and bundled,
workspace and all ordered expanded generators; 39 changed Tcl owners and 345
consumer occurrences. New wrappers: zero; module package changes: zero.

Existing module/GUI/manifest predecessor chains were retained because collapsing
them safely would change broader runtime, headless generators and Analysis call
paths outside this assignment. The full inventory records their source definitions
and consumers, including module enabling, configuration, queued import and preview
owners. Separate-release wrapper remediation remains in the authoritative TODO;
this release neither asserts they are gone nor blocks the assigned corrections.
Affected authority-catalog and API documentation entries were updated together.
`DEV089_CHANGED_FILES.json` supplies the exact final file list.

## Preservation, bounds and acceptance

Original screenshots, user scientific Sessions, original surface/Thermal sources,
installation identity and all historical archives are guarded by SHA-256 inventories.
GUI tests and actual imports use disposable private copies/fixtures and isolated
configuration/identity directories. No scientific module, public API signature,
source coordinate, original RAW file or external package was rewritten.

The repaint correction is validated on this Debian Tk 8.6.16 / existing VcXsrv
multiwindow direct-network environment. Other X servers/compiled native transports
were not claimed tested. No proof exists for the original historical trigger or
for the earlier documentation mask; recurrence there belongs to the unfinished
TODO. All-format import/codec/device checks and previously unfinished broader
Native3D capabilities remain out of scope.

Authoritative TODO contains unfinished work only, including manual acceptance and
retained separate tasks. Completed BUG-001–006 intake items are removed only after
final installed verification; original intake is preserved in release evidence.
Restart the user's existing GUI to load dev089; already-running user processes
were not killed or silently upgraded. Stop for manual acceptance.
