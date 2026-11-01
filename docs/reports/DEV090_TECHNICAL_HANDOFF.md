# GX-TXT 0.9.8.10-dev-090 — Appearance technical handoff

Incremental successor to delivered dev089; manual acceptance remains pending.
The complete dev090 assignment, dev089 handoff, current continuity/TODO,
configuration rules and relevant script catalog entries were read before work.
Baseline archive/restore SHA-256 is
`beafbb4b3414ec7954d704ff259a09856af04447bf9dcc581dbd51f5c44f3dfd`.
Archive, expanded and installed dev089 matched 5575 files; baseline identity,
original screenshots/scientific Sessions and all historical section archives were
inventoried and protected. No prior release is replaced.

## Delivered behavior and ownership

Appearance is the rightmost Configuration subtab. The actual final notebook owner
also appends Installation Identity after Modules, so the preserved final sequence
is Storage, Runtime, Computation, Libraries, Scripts, Viewers, Modules,
Installation Identity, Appearance. All thirteen top-level pages retain dev089 order.

Five user-scope fields use the existing Configuration API and configuration.ini:
`ui.theme=system`, `ui.font_family=system`, `ui.font_size=system`,
`ui.x11_popup_repair_enabled=1`, `ui.x11_popup_repair_delay_ms=150`.
The theme selector adds System/default to exactly the interpreter's installed
`ttk::style theme names`; no themes are installed/hardcoded. Named GUI font family
and size are optional, preserve heading weight and monospace family distinctions,
and accept System/default or supported installed family / 8–24 point size.
Relative named-font sizes are retained. Existing explicitly sized private fonts
and scientific output fonts remain under their current owners.

Theme and font changes are applied once immediately after requiring Tk and before
GUI/style/native-host construction. Save displays the need to restart GX-TXT;
existing windows retain their visuals. A real dev089 probe demonstrated that a
custom GXSelected.TLabel background defined on default disappears on switching
to clam (magenta → #dcdad5). Applying at startup lets the existing owners build
styles under the selected theme and avoids unsafe live native-embed relayout.
No product live-theme engine or automatic restart was added. Revert unsaved
appearance restores saved choices; Restore defaults stages only these five fields
and requires Save. Actual theme/Tk/named-font/scaling readout and nonfatal
unavailable-theme/font warnings remain available. Startup fallback uses the
interpreter's original theme, preserving the missing saved choice until corrected.

Appearance scrolls vertically, descriptions wrap to its width and its own actions
use the existing adaptive GUI control layout. Arbitrary colors, private padding,
icon/canvas styles and editable display scaling are excluded for documented owner
and lifecycle reasons. ttk does not imply complete dark-mode coverage of classic
Tk canvas/text or scientific engines. No scientific Viewers fields were moved.
Native2D theme/font/scaling layout signatures are preserved unchanged.

## Remote popup compatibility: cause and retained repair

The already demonstrated dev089 defect was stale/incomplete Win32 popup
presentation on the existing HC-Consult/VcXsrv multiwindow direct-network X11
path. Tcl/Tk values/styles and XComposite redirected pixmap text were correct;
only native screen pixels contained the rectangular mask. Entries intersecting
that stale screen-space rectangle disappeared while others remained visible and
all remained selectable. Native repaint and complete-region XDamage restored the
exact missing pixels. This was remote native presentation, not local Tcl/Tk empty
values or a theme defect, and the connection is direct TCP, not SSH forwarding.
Dev089's precise before/after evidence and root-cause bounds are retained in its
original report/evidence. The original historical trigger and the documentation
navigator mask's equivalence remain unproved; dev090 does not reinvestigate them.

The pragmatic dev089 full-root-rectangle XDamage mechanism and HC-Consult server
gate are retained. Configured post-map delay replaces the constant 150; no actual
invisible-pixel detection is promised. Map replaces an older timer for the same
popup; Unmap/Destroy cancel it. Execution checks mapped existence, enable state
and server gate again. Save disabled cancels pending timers; disabled startup does
not load the optional library. An already loaded native library is safely retained
but future notifications are suppressed. Local Xorg and other servers install no
recovery binding/load. Native transport has only a bounded initialization check
for XDamage 1.1 and XFixes 2.0; load/dependency failures become a Configuration
status, not GUI failure. Native helper ABI and region/update behavior are unchanged.
Status distinguishes active, disabled, not applicable and unavailable. Delay is
validated 25–2000 ms; 150/300/500 shortcuts are available. 150 ms remains the tested
baseline, not a universal minimum or a claim that longer delay is better.

## Focused actual GUI evidence

Evidence root: `_evidence_appearance_dev090`. Private XDG/identity settings and
new Sessions isolate all actions. Normal local Debian Xorg :1 / GDM Xauthority
and the existing Windows direct-network display 192.168.1.111:0 were used;
no Xvfb substitute or remote infrastructure/configuration change occurred.

| Test | Result / evidence |
|---|---|
| Pinned baseline and Configuration before view/style probe | baseline.json; baseline-gui |
| Rightmost tab, exact dynamic theme list, native editing/Save/Revert/defaults, invalid delay and preserved unrelated fields | local-final.log; APPEARANCE_LOCAL_PASS |
| Saved clam/font11/delay500 survive fresh GUI; explicit restart semantics | restart-clam.log; RESTART_PERSISTENCE_PASS |
| All installed themes clam/alt/default/classic, normal/selected/focus/disabled controls and readable popup rows | matrix.log; local-matrix.json; matrix-* screenshots |
| Saved serif11 / monospace distinction, normal/narrow layout; maximum24pt scrolling/actions/keyboard access | matrix-font and matrix-large |
| Unavailable saved theme safely falls back, warning and Configuration accessible | matrix-fallback |
| Sixteen ALWAYS providers, categorized browser/native CSV folder queue and actual two-file import, canonical shuffled schema selectors, modern16-point XYZ/orientation/orbit/Exit | restart-clam.log; DEV089_REGRESSION_PASS; scientific screenshots |
| Save leaves private Session manifest unchanged and contains no appearance keys | restart-clam.log |
| Fresh disabled recognized-server startup does not load helper; missing-helper full GUI starts with diagnostic | disabled-start.log / missing-start.log |
| Native Windows popup enabled150/300/500, disabled selection, cancellation and rapid close/reopen | remote-final.log / remote-native.log; native popup-*.png |
| Actual Windows startup saved serif11/clam and each theme's native popup/selection/disabled state; narrow Appearance | remote-theme-complete.log / theme-native-complete.log; remote-theme-complete/*.png |

Execution traces on the native command record exactly one request at 150, 300 and
500 ms after mapping respectively; disabled records zero, with native selection
still working. Rapid close/reopen at configured500 produces exactly one request
for the latest map (501 ms); disabling while pending records zero and an empty
timer inventory. Native Windows captures prove displayed pixels rather than only
X11 backing-store screenshots. Diagnostic transient theme switches in the private
remote test verify rendering; they are not a delivered live-preview feature.

An early private capture was refused by its occlusion guard and is excluded from
acceptance. The user then confirmed the desktop idle. Remote input coordinates
are converted from Tk-relative client coordinates through actual Win32 ClientToScreen
rather than trusting an asynchronous X11/Win32 root-position snapshot. A separate
theme-capture trial double-converted a Win32 point; it did not open the popup and
is excluded. A subsequent theme-transition trial reused an SMB-cached point
file and is also excluded. Final captures use unique coordinate files, reset the
relative point before ClientToScreen, and assert that the native click mapped
the Tk popup before capture. No capture
of an unrelated user window was retained. An early local harness attempt found the
new tab call placed in the wrong similarly named refresh occurrence; this was
corrected at the final owner and all final tab tests passed. Trial logs are distinct
from the final acceptance logs; no false PASS is claimed for those attempts.

## Consumer inventory, APIs and preservation

Actual owning implementations were changed; no Tcl rename/alias wrapper was
added. The audit scans all 101 installed modules, current CORE/GUI/bridge/viewer
sources, bundled/workspace generators and all 56 ordered expanded generators.
Existing GUI/module/manifest wrapper chains are inventoried with their actual
consumers and unchanged definitions. Safely collapsing those broader chains
requires a separate release and remains unfinished work. Module package bytes,
all16 Acquisition identities/versions/dependencies/handlers and public scientific
API signatures are unchanged. Configuration/appearance/popup catalog entries and
API/help documentation were updated together. GUI-only APIs need no Script Bridge.
Exact changed-file inventory is `docs/reports/DEV090_CHANGED_FILES.json`; full
consumer inventory is in packaged dev090 evidence/audit-final.

## Limits and installation boundary

Tests cover the actual Debian Tk8.6.16 / installed four themes and existing Windows
VcXsrv path. Optional-helper absence was reproduced with a private linked framework
variant, not by removing installed dependencies or changing server extensions.
The load-time extension guards are compiled and exercised on the available server;
physically removing XDamage/XFixes from that server was intentionally not performed.
Theme/font changes require user restart; already running user GUIs are untouched.
Explicit private fonts and classic Tk colors remain outside global ttk coverage.
Appearance font changes affect GUI named-font users only, not scientific data,
coordinate systems, renderer settings, output fonts or Session schemas. Large
fonts may abbreviate tab labels; Tk notebook keyboard navigation and Appearance
scroll/actions remain usable. This is a limited regression, not every scientific
module/device/codec test campaign. Unrelated unfinished TODO items are retained.

A single new dev090 archive/expanded/restore pair is delivered, active dev089 is
preserved as rollback, and the installed successor is verified. The external
handoff appends final archive SHA, installation receipt and fresh installed GUI
checks after publication. Stop for manual acceptance.

Final consumer audit: 101 installed module packages, 2140 source files, 19 changed Tcl owners and 167 consumer occurrences; new rename chains: 0. All package bytes unchanged.
