# dev086 technical report

Baseline: corrected published dev085, archive SHA-256
`87f3ebe274e2ba69d01b5712bdfc19c15756314bc10898ef97301ed373fd4e7f`.
Fresh development tree: `_work_gxtxt_dev086_ui`. Manual acceptance PENDING.

The existing thirteen main tabs retain their pages and navigation. The final five
are Projects → Modules → Viewers → Configuration → Help. Only notebook insertion
order changes; the corrected Project Home/Projects code and Project transport,
identity/provenance/persistence services are byte-preserved.

Modules now provides Module State / Runtime / Tools menus, the existing manual
button, Search/Type/Group plus All/CORE/Non-CORE filtering and independent Plot,
Script Octave and Script Python controls. ALWAYS (`selectable=0`) rows and the
three quick-control rows are hidden. The lifecycle still keeps ALWAYS modules
enabled; Configuration retains their installed-descriptor inspection. Quick
checkboxes call existing moduleSetEnabled and rebuild Analysis using its existing
builder; disable preserves saved configuration. Right-click selects the clicked
module and offers Enable/Disable/Toggle. Double-click retains its original callback.
Header adapts to 920 px minimum width while keeping quick controls on the right.
The existing optional Script Workspace control remains available.

Script Octave/Python descriptors change only core=0 → core=1. Their selectable=1,
default_enabled=0 and all implementations are preserved. This is distribution
protection, not forced enablement. Plot was already CORE.

Runtime Reset calls unchanged resourceLifecycleModuleReset: validated current
Session and active Script/Project references, real deletion of cache/<module-id>,
and refresh through existing resource views. It preserves canonical Datasets,
notes, Graph Series, Sessions, configuration and published analysis/render results.
It does not clear analysis/ render caches or kill running jobs; those are outside
the existing reset contract. No alternative lifecycle API was introduced.

Plugin administration is reachable only through Configuration → Modules → Plugin
Manager. The same manager gains Update selected via the existing installer callback
and its own selected ID, including managed non-module types. Install/bundle support
and existing uninstall remain authoritative. Main Modules no longer has installation
entry points. CORE and ALWAYS removal is disabled and enforced by the existing
uninstall operation. No second manager, Configuration redesign or plugin rewrite.

Plots groups 26 existing actions into six named menus. Refresh, Rerender and Open
PNG 1:1 remain direct (29 total). Menus invoke the original retained button widgets;
the postcommand reads each original enabled/disabled state. All callback and shortcut
owners, capability checks, Graph Series, rendering and persistence stay unchanged.
Original extension button paths remain valid; compact rows replace the scrolling
button strip. The annotated/native ZIP and PNG exports, ZIP import, clone/edit/delete,
all three rerender paths, presentation/data editors and Session Save/reopen were
operated with real Xorg input on a generated scientific plot.

Focused evidence uses private XDG, identity, script and Session directories. Plugin
install/update/remove operate in a complete disposable framework copy. Dataset
SHA and Graph Series persistence were checked; no user Session was opened or deleted.
Modules and Plots acceptance ran serially in fresh real GUI processes with the same
private fixture. The final native Save confirmation was answered with Xorg Return
after visual inspection (save-confirmation-input.json); no callback was replaced.
Plain application entry was also visually inspected. All seven focused matrix rows
PASS; manual acceptance remains the user's separate step.

Development fixture failures are retained in `_evidence_ui_dev086`: initial seed
attempts used the wrong API version/contract and an unnormalized Series record;
these were corrected using the public graphSeriesSet and compatible table contract.
Early GUI driver attempts had a Tk command name collision, window-manager focus/mapping,
popdown scrolling/key selection, directory-navigation confirmation, nested export
paths and repeated native-dialog handling issues. Those
incomplete attempts are excluded; final evidence uses native mouse menu selections,
focused native dialogs and the real unchanged callbacks. No production service was
stubbed or renamed. Existing historical Tcl wrappers remain untouched.

Delivery gates protect historical archives, both external package sections,
scientific plugin payloads, native engines and Project authorities. Archive/internal
SHA256SUMS/expanded/active/alias/restore parity is required before handoff.
The authoritative TODO contains unfinished work only, including manual acceptance
and the separately scoped central configurator after Astra's API work.
