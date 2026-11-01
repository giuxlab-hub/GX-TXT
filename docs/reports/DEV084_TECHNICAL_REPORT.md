# dev084 technical report — real operator corrective release

GX-TXT 0.9.8.10-dev-084 starts from immutable published dev083 SHA-256
`16732f962a31a0ea793242edc4b52213605329cdfe06ea8d77c00aebb708fedb`.
**dev083 was NOT accepted. Corrective dev084 is ready for final manual acceptance;
engineering and operator PASS do not constitute user acceptance. No Astra work.**

## Corrected behavior

Storage uses one coherent editor/catalog projection of existing public authorities:
applied context, selected definition and draft are distinct. The global five-role
catalog expands; names retain readable minimum width and paths have horizontal scrolling.
Private Storage initially shows five actual effective values plus per-role source.
Global use is direct; independent namesake copies use the source name when blank;
Edit/Save/Use/Cancel/Remove are explicit, and collisions never overwrite silently.
Readable resizable notices preserve full context/path/errors. Applying validates live
directories; saving an inactive private draft can retain an unavailable path without
applying it. Active private Save updates that definition and refreshes effective fields.

The minimal demonstrated underlying fixes add global Save without Apply, retain the
named applied context through restart/Session initialization, and keep runtime mirrors
consistent with native chooser resolution. Atomic failure paths preserve registry/
preference preimages. Clean preparation clones omit source-owned and earlier-carrier
Session-owned absolute private paths; shared storage roots and @session references
remain, with normal fallback for unavailable targets. Lossless Portable transport
preserves private definitions unchanged.

Projects uses ID-bound compact rows, full-row theme-aware selection, keyboard navigation,
an exact single export target, and import enabled by Project selection alone. Info fills
the same right canvas with Overview/Datasets/Modules & Scripts/Documents/Origin &
Technical, readable note/manual labels, verified rendered Markdown, accessible path/hash
details and honest no-documents/resource failures. Historic empty names have a display-only
directory fallback. Delete completion names the actual retained recovery location;
Portable completion explains dependency diagnostics in readable lines.

Headless inspection/document reads move from the GUI into the existing CORE family with
unchanged signatures. Additive guarded Dataset availability checks location/size without
hashing large scientific payloads; integrity remains explicitly not_checked until the
normal scientific/Portable reader verifies it. The read-only Python/Octave binding omits
absolute paths. Existing scientific Dataset implementations, Instrument/Manifest/
persistence services, plugins, native engines and generators are retained.

## Real operator campaign and visual review

Primary tests launch the plain unmodified application entry on the authenticated Xorg
desktop. desktop.py sends coordinates/keyboard/native chooser events, never Tcl widget
queries, callback evaluation or CORE actions. seed/enrich/legacy-copy scripts only prepare
scientific prerequisites; postflight/audit only read outcomes. Two separate private XDG/
installation contexts A/B protect the user's Sessions/serial. Every matrix row references
screens actually inspected by the agent. Session/profile operations include Save,
change/reopen and restart; ephemeral selection is intentionally not saved science.
The rich source has three Datasets (two contracts), a 20,000-row trace, saved graph and
Workspace, script, hand-written note and sixteen historic manual snapshots. The actual
1.9 GiB Audio and Statistics Sessions are disposable full copies; full original inventories
and copied scientific files are checked. No expensive scientific rerun was substituted
for inspection. Default Xorg, 1280×720 and 1680×900 were operated and reviewed. Supplemental
clam and dark/yellow host themes exercise actual controls without changing desktop
preferences or application callbacks; these are clearly distinguished from plain-entry
journeys and are not a new product theme setting.

Visual review found and corrected: initially empty effective fields, truncated failures,
absent catalog, ambiguous selection, blank Info geometry, snapshot ordinal dictionary text,
literal newline empty states, keyboard focus going to the Project list, and names shrinking
on resize. The historic Statistics campaign additionally exposed an empty-name row; its
display fallback was fixed/repeated. The B copy exposed an imported absolute path back
to an earlier carrier; the preparation-only safe-copy rule was fixed and exercised.

Retained early reproduction/development evidence includes failures and harness mistakes:
the former Xorg window search could select another fixture when two ran concurrently;
those ambiguous steps were excluded and repeated with uniquely newly mapped windows.
Early Ctrl+A/chooser-coordinate attempts, premature screenshots during loading, and
mis-targeted row clicks are not credited. The early cumulative A application.log retains
one X_UnmapWindow BadWindow from that old harness sequence; fresh per-launch output is
separate and clean. xdotool window enumeration can report transient X_QueryTree BadWindow
while old windows are destroyed; it is not application output. Two audit-harness mistakes
(notes are Manifest fields, and legacy INI allows repeated sections) were corrected;
the first error log remains evidence. Library editor Close does not offer a new unsaved
decision flow; native Save/Discard/Cancel was exercised on actual Instrument notes.
The initial publication guard also refused a signature-harness identity directory beside
the release catalog before any publishing mutation. That fixture identity was retained
under evidence and explicit private roots were enforced; the release catalog was restored.
Screens named new-creator-after-rotation, private-missing-directory-readable from its
first saved-draft attempt, and earlier keyboard/preview attempts are superseded by the
explicit corrected matrix references. No screenshot name alone asserts success.

## Before/after evidence for each reported complaint

| User-observed failure | Published dev083 reproduction | Corrected dev084 screen |
|---|---|---|
| Global catalog | [before](../evidence/dev084/operator-before/global-catalog.png) | [after](../evidence/dev084/operator-final/global-catalog-fixed-small.png) |
| Session effective values/scope | [before](../evidence/dev084/operator-before/private-empty-effective.png) | [after](../evidence/dev084/operator-final/private-save-only-restarted.png) |
| Blank-name global copy | [before](../evidence/dev084/operator-before/blank-name-copy-error.png) | [after](../evidence/dev084/operator-final/storia-copy-blank-name-success.png) |
| Readable validation | [before](../evidence/dev084/operator-before/blank-name-copy-error.png) | [after](../evidence/dev084/operator-final/private-write-failure-readable.png) |
| Selection and import/export targets | [before](../evidence/dev084/operator-before/selection.png) | [after](../evidence/dev084/operator-final/rich-large-target.png) |
| Useful Markdown-heavy Info | [before](../evidence/dev084/operator-before/markdown-heavy-info-before.png) | [after](../evidence/dev084/operator-final/rich-documents-final-large.png) |
| Empty Documents Info | [before](../evidence/dev084/operator-before/no-markdown-info-before.png) | [after](../evidence/dev084/operator-final/empty-documents-final-large.png) |
| Minimum size / responsiveness | [before](../evidence/dev084/operator-before/minimum-before.png) | [after](../evidence/dev084/operator-final/historic-audio-info-ready.png) |

## Focused regression and public interoperability

api/storage/identity/transaction/Portable/legacy/Bridge tests are retained as technical
supplements. The changed clone path has final regression-final.log; real historic Audio
clone/save/reopen and full original preservation have historic-compat.log. The final
signature inventory preserves all 3360 old argument/default contracts, 439 effective
Dataset bodies and 31 Instrument/Manifest/persistence bodies. Complete scientific
package files from the A export match B re-export and Tools export except the explicitly
organizational/transport Manifest; all three canonical Dataset identities/bytes persist.
The original source graph/Workspace remain; preparation clones contain neither source
Datasets nor Workspaces/graphs/observations. Instruments added afterward are new setup.
Creator A is retained through rename/move/import/re-export/rotation; receiver B is
recorded separately, B duplicate has B creator and imported parent, legacy stays unknown.
The user's real installation identity is never rotated by the campaign.

Public Astra boundary remains the existing Installation Identity, Project Management,
Session Origin/Inspection and validated Portable APIs. Foreign declared creators are
lineage, not authentication. No Dataset/document/geometry origin authority, competing
registry, framework redesign or provenance migration is introduced. Details are in
SESSION_STORAGE_PROFILES_API_v1, SESSION_INSPECTION_API_v1 and
PROJECT_EXPERIMENT_MANAGEMENT_API_v1 manuals. Explicitly unsupported operations are
private Rename and multi-export; no requested supported journey remains failed.

## Operator-journey acceptance matrix

| Operation | Visible starting state / controls | Observed result | Reviewed screen | Persistence / scientific checks | Status / limits |
|---|---|---|---|---|---|
| A01 | Fresh B launch → Configuration → Installation Identity | Discoverable read-only initial ID and first history row | [first-run-identity](../evidence/dev084/operator-B/first-run-identity.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A02 | B close/restart → Installation Identity | Same ID and history retained | [B-restarted-stable-identity](../evidence/dev084/operator-B/B-restarted-stable-identity.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A03 | Fresh B → Configuration → Storage | Truthful unnamed-global context and empty saved catalog; five effective fields populated | [first-run-empty-storage](../evidence/dev084/operator-B/first-run-empty-storage.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A04 | A Storage → Show defaults/cache → edit cache → Save user defaults | Ordinary preferences saved; identity not rotated | [storage-defaults-to-change](../evidence/dev084/operator-final/storage-defaults-to-change.png), [preferences-save-identity-retained](../evidence/dev084/operator-final/preferences-save-identity-retained.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A05 | A Storage → New → five A directory fields → Save | STORIA_TELECOMANDO saved without applying | [global-A-saved](../evidence/dev084/operator-final/global-A-saved.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A06 | A Storage → New → five B directory fields → Save & Apply | SECOND_SITE becomes applied; five native roles change | [global-B-applied](../evidence/dev084/operator-final/global-B-applied.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A07 | A global catalog → select STORIA_TELECOMANDO row | All five saved values immediately editable; applied B remains distinct | [global-A-selected-final](../evidence/dev084/operator-final/global-A-selected-final.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A08 | A selected A profile → Save & Apply; switch B then return A | Explicit A/B/A applied state and preserved definitions | [global-A-applied-final](../evidence/dev084/operator-final/global-A-applied-final.png), [global-A-return](../evidence/dev084/operator-final/global-A-return.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A09 | A global catalog → Edit selected → change Export → Save | Inactive B update does not switch A; updated role retained | [global-update-corrected](../evidence/dev084/operator-final/global-update-corrected.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A10 | A Edit selected → change draft → Cancel / Show applied | Draft discarded; actual applied values return | [global-cancel-corrected](../evidence/dev084/operator-final/global-cancel-corrected.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A11 | A New global → Browse Session root → native chooser → Save | Real directory with whitespace chosen and saved | [browsed-profile-saved](../evidence/dev084/operator-final/browsed-profile-saved.png), [browsed-profile-committed](../evidence/dev084/operator-final/browsed-profile-committed.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A12 | A select browsed global → Remove → No | Profile and directory retained | [remove-global-cancelled](../evidence/dev084/operator-final/remove-global-cancelled.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A13 | A select browsed global → Remove → Yes | Only saved profile removed; directory remains | [remove-global-complete](../evidence/dev084/operator-final/remove-global-complete.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A14 | A New global → invalid name → Save | Full validation and recovery guidance readable | [invalid-name-readable](../evidence/dev084/operator-final/invalid-name-readable.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A15 | A New global → existing name → Save | Non-overwriting duplicate error readable | [duplicate-name-complete](../evidence/dev084/operator-final/duplicate-name-complete.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A16 | A global draft → missing directory → Save & Apply | Directory/path and corrective choices readable; applied state retained | [missing-directory-complete](../evidence/dev084/operator-final/missing-directory-complete.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A17 | A global draft → Save with fixture parent read-only | Full permission failure; exact preference preimage retained | [write-failure-readable](../evidence/dev084/operator-final/write-failure-readable.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A18 | A close/restart → global Storage | Named applied A and complete five roles survive | [global-restart-retained](../evidence/dev084/operator-final/global-restart-retained.png), [global-catalog-fixed-small](../evidence/dev084/operator-final/global-catalog-fixed-small.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A19 | Applied A → Acquisition Browse input | Native Acquisition chooser starts in A acquisition | [native-acquisition](../evidence/dev084/operator-final/native-acquisition.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A20 | Applied A → Session Open | Native Open chooser starts in A open directory | [native-open-session-correct](../evidence/dev084/operator-final/native-open-session-correct.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A21 | Applied A → New Session root chooser | Native root chooser starts in A Sessions directory | [native-new-root](../evidence/dev084/operator-final/native-new-root.png) | Applied global catalog/role persistence after restart; storage.log exact failure preimages | PASS  |
| A22 | B global → Configuration export/load | Both native Manifest choosers start in B manifest role | [manifest-native-global-initial](../evidence/dev084/operator-B/manifest-native-global-initial.png), [manifest-load-chooser](../evidence/dev084/operator-B/manifest-load-chooser.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A23 | A Project Export / B re-export | Native Export role starts in each installation’s applied export directory | [export-scientific-chooser](../evidence/dev084/operator-final/export-scientific-chooser.png), [B-reexport-chooser](../evidence/dev084/operator-B/B-reexport-chooser.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| A24 | A Identity → Rotate without reason | Readable reason requirement; serial unchanged | [identity-reason-required](../evidence/dev084/operator-final/identity-reason-required.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A25 | A Identity → reason → Rotate → No | No rotation; original history retained | [rotation-cancel-unchanged](../evidence/dev084/operator-final/rotation-cancel-unchanged.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A26 | A Identity → reason → Rotate → Yes | New serial; previous ID/reason retained | [rotation-new-and-history](../evidence/dev084/operator-final/rotation-new-and-history.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A27 | A close/restart → Identity | Rotated serial and two history entries retained | [A-rotation-restart-retained](../evidence/dev084/operator-final/A-rotation-restart-retained.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| A28 | Normal main tabs and open Sessions | Human Session identifier, preserved ordered scientific tabs | [rich-opened-header](../evidence/dev084/operator-final/rich-opened-header.png), [historic-audio-waveform-preview](../evidence/dev084/operator-final/historic-audio-waveform-preview.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| B01 | A open rich Session → Configuration / Manifest → Storage Profiles | Five actual effective global fields visible before Edit | [private-initial-effective](../evidence/dev084/operator-final/private-initial-effective.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B02 | A private page → select global STORIA_TELECOMANDO; name blank → Create independent private copy | Source name proposed naturally; independent namesake created | [storia-global-blank-private-name](../evidence/dev084/operator-final/storia-global-blank-private-name.png), [storia-copy-blank-name-success](../evidence/dev084/operator-final/storia-copy-blank-name-success.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B03 | A copied private → edit blank Acquisition, private Manifest and @session Export → Save & Use | Mixed fallback and per-role sources; global catalog exact preimage retained | [mixed-private-effective-final](../evidence/dev084/operator-final/mixed-private-effective-final.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B04 | A same selected global → Copy again | Readable namesake conflict; no overwrite | [same-name-copy-conflict-real](../evidence/dev084/operator-final/same-name-copy-conflict-real.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B05 | A private page → global selector → Use global profile | Uses global directly, keeps independent copies | [global-switch-real](../evidence/dev084/operator-final/global-switch-real.png), [B-use-global-context](../evidence/dev084/operator-B/B-use-global-context.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B06 | A private catalog → select STORIA → Use selected private | Private saved snapshot takes effect; global catalog separate | [private-switch-real](../evidence/dev084/operator-final/private-switch-real.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B07 | Mixed private → Configuration export chooser | Native Manifest chooser resolves private Session metadata | [private-manifest-native-initial](../evidence/dev084/operator-final/private-manifest-native-initial.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B08 | B mixed private → Tools → Export Portable | Native Export chooser resolves @session/exports private | [tools-private-export-chooser](../evidence/dev084/operator-B/tools-private-export-chooser.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| B09 | A private page → New private → Save & Use blank-role PRIVATE_TEMP | Private created/applied, all roles truthfully global fallback | [private-temp-applied](../evidence/dev084/operator-final/private-temp-applied.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B10 | A private Edit → change draft → Cancel / Show effective | Saved values/effective context restored | [private-cancel-restored](../evidence/dev084/operator-final/private-cancel-restored.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B11 | A private Remove → No | Existing private copy retained | [private-remove-cancel](../evidence/dev084/operator-final/private-remove-cancel.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B12 | A temporary private Remove → Yes | Temporary removed, fallback restored, directories retained | [private-remove-complete](../evidence/dev084/operator-final/private-remove-complete.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B13 | A close/change/restart → rich Session → private Storage | Applied STORIA and independent copies/mixed fields retained | [source-profile-reopened-controlled](../evidence/dev084/operator-final/source-profile-reopened-controlled.png), [private-save-only-restarted](../evidence/dev084/operator-final/private-save-only-restarted.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B14 | A New private → PRIVATE_SAVE_ONLY → Save private | Inactive profile saved without switching active STORIA | [private-save-without-apply](../evidence/dev084/operator-final/private-save-without-apply.png), [private-save-only-effective-retained](../evidence/dev084/operator-final/private-save-only-effective-retained.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B15 | A close/restart → open rich Session | Inactive PRIVATE_SAVE_ONLY and active STORIA retained separately | [private-save-only-restarted](../evidence/dev084/operator-final/private-save-only-restarted.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B16 | A New private → bad/name → Save | Readable scoped invalid-name validation | [private-invalid-name-readable](../evidence/dev084/operator-final/private-invalid-name-readable.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B17 | A New private → STORIA_TELECOMANDO → Save | Readable scoped duplicate refusal | [private-duplicate-readable](../evidence/dev084/operator-final/private-duplicate-readable.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B18 | A saved private draft with missing Manifest path → Save & Use | Apply fails with complete unavailable path; draft retained | [private-missing-directory-readable](../evidence/dev084/operator-final/private-missing-directory-readable.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B19 | A private Edit → Save while fixture metadata directory read-only | Complete failure, exact private registry SHA retained; permissions restored | [private-write-failure-readable](../evidence/dev084/operator-final/private-write-failure-readable.png) | Private definitions/active state after restart; source Dataset hashes unchanged | PASS  |
| B20 | A open rich Session → Session → Duplicate Experiment → Create | Preparation duplicate created; no source Datasets/Workspace/graphs/observations | [duplicate-experiment-dialog](../evidence/dev084/operator-final/duplicate-experiment-dialog.png), [clone-info-no-scientific](../evidence/dev084/operator-final/clone-info-no-scientific.png), [clone-workspaces-empty](../evidence/dev084/operator-final/clone-workspaces-empty.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart; regression-final.log and source Workspace/graph retained | PASS  |
| B21 | A duplicate → private Storage → change/reopen | Safe shared roots and relative references retained; source-owned Manifest omitted | [clone-safe-private-correct](../evidence/dev084/operator-final/clone-safe-private-correct.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| B22 | B imported Session → Duplicate Experiment → private Storage / Origin | Earlier carrier-owned absolute path omitted; new B creator and imported parent | [B-duplicate-safe-profiles](../evidence/dev084/operator-B/B-duplicate-safe-profiles.png), [B-duplicate-new-creator-parent](../evidence/dev084/operator-B/B-duplicate-new-creator-parent.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart; retained recovery audited | PASS  |
| B23 | Private profile Rename | No dedicated Rename operation advertised | [private-save-only-restarted](../evidence/dev084/operator-final/private-save-only-restarted.png) | Not supported | SKIP Changing editor name saves another definition; no rename button or invented contract |
| C01 | A Projects → Create → named A and B | Two visible named Projects created | [two-projects-created](../evidence/dev084/operator-final/two-projects-created.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C02 | A Project A → Edit → Save | Complete reviewed Project display name persists | [project-edit-dialog](../evidence/dev084/operator-final/project-edit-dialog.png), [reassociated-confirmed](../evidence/dev084/operator-final/reassociated-confirmed.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C03 | A named Project → New Session here → Create | Named Project and resolved root clearly shown; new Session belongs there | [new-named-session-dialog](../evidence/dev084/operator-final/new-named-session-dialog.png), [named-created-row](../evidence/dev084/operator-final/named-created-row.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C04 | A Default → New Session here → Create | Standalone Session belongs to permanent Default | [standalone-create](../evidence/dev084/operator-final/standalone-create.png), [standalone-row](../evidence/dev084/operator-final/standalone-row.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C05 | A Session Open native chooser → genuine dev082 copy | Legacy unlinked Session encountered in Default; unknown creator preserved | [legacy-default-browser](../evidence/dev084/operator-final/legacy-default-browser.png), [legacy-unknown-origin](../evidence/dev084/operator-final/legacy-unknown-origin.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C06 | A Projects → click full rich row | Unmistakable selected row and exact Export target | [rich-large-target](../evidence/dev084/operator-final/rich-large-target.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart; selection ephemeral by design | PASS  |
| C07 | A row click → Down; long-list wheel → bottom | Keyboard and mouse selection/scroll work with ID-bound rows | [keyboard-fixed](../evidence/dev084/operator-final/keyboard-fixed.png), [rich-list-ready](../evidence/dev084/operator-final/rich-list-ready.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart; focus/selection not scientific persistence | PASS  |
| C08 | A resize browser to 1280×720 / 1680×900 | Long names wrap; row controls and targets reachable | [rich-list-ready](../evidence/dev084/operator-final/rich-list-ready.png), [rich-large-target](../evidence/dev084/operator-final/rich-large-target.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C09 | Experiment multi-selection/export | UI explicitly offers one Session per validated Portable package | [rich-large-target](../evidence/dev084/operator-final/rich-large-target.png) | Not supported | SKIP No multi-export claim or unvalidated combined scientific ZIP |
| C10 | A named row → Rename → Save | Full new name persists, original directory/ID/creator retained | [rename-session-dialog](../evidence/dev084/operator-final/rename-session-dialog.png), [renamed-session-row](../evidence/dev084/operator-final/renamed-session-row.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C11 | A Rename draft → Cancel | Existing name retained | [renamed-session-row](../evidence/dev084/operator-final/renamed-session-row.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart; coordinate journal includes cancelled draft | PASS  |
| C12 | A row → Move to Default | Organization moves; Session bytes and directory retained | [default-members-now](../evidence/dev084/operator-final/default-members-now.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C13 | A Default row → Open | Correct Session opens through normal controller | [reassociated-row](../evidence/dev084/operator-final/reassociated-row.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C14 | A select named Project → Move open Session here | Ordinary GUI reassignment restores named membership | [reassociated-confirmed](../evidence/dev084/operator-final/reassociated-confirmed.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C15 | A rich row → Info → Overview | Useful summary: three Datasets/two contracts, script/notes/origin | [rich-overview-final](../evidence/dev084/operator-final/rich-overview-final.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C16 | A rich Info → Datasets | Contract/format and guarded presence; integrity explicitly not checked | [rich-datasets-final](../evidence/dev084/operator-final/rich-datasets-final.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C17 | A rich Info → Modules & Scripts | Configured/enabled/Run distinguished from Dataset-based use evidence | [rich-modules-final](../evidence/dev084/operator-final/rich-modules-final.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C18 | A rich Info → Documents | Human notes and sixteen manual snapshots classified; real Markdown rendered | [documents-numbered-corrected](../evidence/dev084/operator-final/documents-numbered-corrected.png), [rich-documents-final-large](../evidence/dev084/operator-final/rich-documents-final-large.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C19 | A Documents → select module manual | Existing manual renders; ordinals 1–4 distinguish historic snapshots | [module-manual-preview](../evidence/dev084/operator-final/module-manual-preview.png), [rich-documents-final-large](../evidence/dev084/operator-final/rich-documents-final-large.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C20 | A selected document → Document details | Full relative path/hash accessible and selectable | [document-details-real](../evidence/dev084/operator-final/document-details-real.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C21 | A empty Session → Info → Documents | Explicit zero Markdown state; no files fabricated | [empty-documents-corrected](../evidence/dev084/operator-final/empty-documents-corrected.png), [empty-documents-final-large](../evidence/dev084/operator-final/empty-documents-final-large.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C22 | A broken fixture → Info → Datasets | Missing payload highlighted honestly; open rich Session unchanged | [missing-dataset-detail-final](../evidence/dev084/operator-final/missing-dataset-detail-final.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C23 | A fixture directory temporarily displaced → Refresh → Info | Unavailable row and complete contextual error; Back accessible; active Session unchanged | [missing-session-row](../evidence/dev084/operator-final/missing-session-row.png), [missing-session-info-readable](../evidence/dev084/operator-final/missing-session-info-readable.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart; own fixture directory restored exactly | PASS  |
| C24 | A Info → Origin & Technical / Back | Declared creator and IDs readable; inspection does not switch active Audio | [source-creator-after-rotation-active-audio](../evidence/dev084/operator-final/source-creator-after-rotation-active-audio.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C25 | A selected rich row → Export → native Save | Correct full scientific Session exported; readable completion | [export-scientific-chooser](../evidence/dev084/operator-final/export-scientific-chooser.png), [export-completion-real](../evidence/dev084/operator-final/export-completion-real.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json; B final completion uses human diagnostics | PASS  |
| C26 | A empty receiving Project, no Experiment selection → Import | Import enabled by Project alone; native package selection/destination | [import-no-existing-selection](../evidence/dev084/operator-final/import-no-existing-selection.png), [import-native-chooser](../evidence/dev084/operator-final/import-native-chooser.png), [import-destination-dialog](../evidence/dev084/operator-final/import-destination-dialog.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C27 | A Import → complete → row Open | Receiving row appears in intended Project; all three Datasets exact | [import-completion-real](../evidence/dev084/operator-final/import-completion-real.png), [imported-open-state](../evidence/dev084/operator-final/imported-open-state.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C28 | A repeat Import with same destination | Complete collision error; no overwrite or partial Session | [import-collision-readable](../evidence/dev084/operator-final/import-collision-readable.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json; transport.log rollback checks | PASS  |
| C29 | A Import traversal/invalid Portable package | Complete unsafe-path rejection; no imported row/partial Session | [invalid-package-real](../evidence/dev084/operator-final/invalid-package-real.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json; transport.log canonical rejection | PASS  |
| C30 | B named Project without row selection → Import missing-provider package | Readable missing module/version; science retained; resolve dependency before Run | [B-missing-provider-readable](../evidence/dev084/operator-B/B-missing-provider-readable.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C31 | A disposable imported Session → Delete → No | Two original rows and data retained | [delete-session-confirmation](../evidence/dev084/operator-final/delete-session-confirmation.png), [deletion-cancel-retains-two](../evidence/dev084/operator-final/deletion-cancel-retains-two.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C32 | A disposable imported Session → Delete → Yes | Only separate Session removed; unrelated scientific receiver retained | [deletion-complete-one](../evidence/dev084/operator-final/deletion-complete-one.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C33 | B disposable duplicate → Delete → Yes | Registry row removed; completion gives full retained recovery path | [B-deletion-recovery-readable](../evidence/dev084/operator-B/B-deletion-recovery-readable.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C34 | A select Default Project | Edit/Delete permanently disabled; Default retained | [default-permanent](../evidence/dev084/operator-final/default-permanent.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C35 | A named Project with receiver → Delete → No | Project/membership retained | [project-delete-cancelled](../evidence/dev084/operator-final/project-delete-cancelled.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C36 | A named Project with receiver → Delete → Yes | Project removed; scientific receiver reassigned to Default safely | [project-deleted-members-default](../evidence/dev084/operator-final/project-deleted-members-default.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C37 | B independent receiving Project → Import A package → Info Origin | A creator retained; B receiver and fresh organizational ID recorded | [B-origin-creator-and-receiver](../evidence/dev084/operator-B/B-origin-creator-and-receiver.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C38 | B imported row → Export → native Save | Re-export retains A science/creator, with B carrier | [B-reexport-completed](../evidence/dev084/operator-B/B-reexport-completed.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C39 | A rotation → inspect old source / create new Session → Info Origin | Old creator unchanged; new creation uses rotated A ID | [source-creator-after-rotation-active-audio](../evidence/dev084/operator-final/source-creator-after-rotation-active-audio.png), [new-creator-after-rotation-corrected](../evidence/dev084/operator-final/new-creator-after-rotation-corrected.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C40 | A duplicate → Instruments → Add Instrument | Generic instance added and enabled through ordinary picker | [add-instrument-actual](../evidence/dev084/operator-final/add-instrument-actual.png), [instrument-added-real](../evidence/dev084/operator-final/instrument-added-real.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C41 | A Instruments → embedded Library → New → Save | Private Library entry created; embedded presentation and Close work | [embedded-library-empty](../evidence/dev084/operator-final/embedded-library-empty.png), [library-new-instrument](../evidence/dev084/operator-final/library-new-instrument.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C42 | A Library → select entry → Edit → Close | Existing editor opens; closes back to embedded Library | [library-edit-existing](../evidence/dev084/operator-final/library-edit-existing.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C43 | A instance Open Notes → Edit → Close → Cancel | Native Save/Discard/Cancel is fully visible; Cancel keeps draft/editor | [instrument-save-discard-cancel](../evidence/dev084/operator-final/instrument-save-discard-cancel.png), [instrument-cancel-retains-editor](../evidence/dev084/operator-final/instrument-cancel-retains-editor.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C44 | A notes Close → Save; edit again → Close → Discard → reopen | Saved calibration note retained; discarded text absent | [instrument-discard-reopen](../evidence/dev084/operator-final/instrument-discard-reopen.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C45 | A Session → Save configuration → change Session → reopen duplicate | Instrument name and saved note retained | [clone-save-notification](../evidence/dev084/operator-final/clone-save-notification.png), [clone-instrument-reopened](../evidence/dev084/operator-final/clone-instrument-reopened.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C46 | B Session → Tools → Export Portable | Existing Tools transport exports full scientific Session | [B-tools-portable-menu](../evidence/dev084/operator-B/B-tools-portable-menu.png), [Tools-export-completion](../evidence/dev084/operator-B/Tools-export-completion.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C47 | B Session → Tools → Import Portable → new destination | Full scientific copy opens and belongs to Default | [Tools-import-completed](../evidence/dev084/operator-B/Tools-import-completed.png), [Tools-import-default-member](../evidence/dev084/operator-B/Tools-import-default-member.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C48 | B Configuration export (.ini) → load configuration only | Configuration round trip works; identity and scientific data retained | [manifest-exported](../evidence/dev084/operator-B/manifest-exported.png), [configuration-only-loaded](../evidence/dev084/operator-B/configuration-only-loaded.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| C49 | B Dataset → long_trace context Activate Dataset → Preview | Real 20,000-row XY preview renders with display-only controls | [dataset-context-activation](../evidence/dev084/operator-B/dataset-context-activation.png), [B-dataset-active-preview-valid](../evidence/dev084/operator-B/B-dataset-active-preview-valid.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C50 | A Open copied historical Statistics → Dataset pointer → Preview | Three historic Datasets present; ambiguous mapping honestly asks for variables | [historic-statistics-datasets](../evidence/dev084/operator-final/historic-statistics-datasets.png), [historic-statistics-preview](../evidence/dev084/operator-final/historic-statistics-preview.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C51 | A Open copied historical Audio → Info / Dataset Preview | 12 Datasets/16 documents; 1.9 GiB Session inspected without payload scan; WAV preview renders | [historic-audio-info-ready](../evidence/dev084/operator-final/historic-audio-info-ready.png), [historic-audio-datasets](../evidence/dev084/operator-final/historic-audio-datasets.png), [historic-audio-waveform-preview](../evidence/dev084/operator-final/historic-audio-waveform-preview.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json; historic-compat.log saved clean clone/reopen | PASS  |
| C52 | A historical Audio → Save configuration → change/restart | Historical scientific files retained; old creator remains unknown | [historic-audio-saved](../evidence/dev084/operator-final/historic-audio-saved.png), [legacy-names-corrected](../evidence/dev084/operator-final/legacy-names-corrected.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| C53 | A historical Statistics row / Info with empty saved name | Readable directory-name fallback; no inspection rewrite of historic name | [legacy-names-corrected](../evidence/dev084/operator-final/legacy-names-corrected.png), [legacy-statistics-info-name-corrected](../evidence/dev084/operator-final/legacy-statistics-info-name-corrected.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |
| D01 | Default Xorg → resize Storage / Info between practical sizes | Readable minimum names/fields/catalog, proportional populated Info | [global-catalog-fixed-small](../evidence/dev084/operator-final/global-catalog-fixed-small.png), [global-catalog-fixed-large](../evidence/dev084/operator-final/global-catalog-fixed-large.png), [rich-documents-final-large](../evidence/dev084/operator-final/rich-documents-final-large.png) | Public readback-final.tcldict and operator-audit.json after Save/change/restart | PASS  |
| D02 | Supplemental clam host theme → real row click / Down | Visible selection and exact export target with larger themed controls | [clam-storage-small](../evidence/dev084/theme-clam/clam-storage-small.png), [clam-selection-correct](../evidence/dev084/theme-clam/clam-selection-correct.png) | Theme only; no callback substitution or desktop preference change | PASS  |
| D03 | Supplemental dark/yellow host theme → row / Down / scroll / Info → resize | Full contrasting selection, readable long names and Markdown at both sizes | [contrast-selection-correct](../evidence/dev084/theme-contrast/contrast-selection-correct.png), [contrast-markdown-small](../evidence/dev084/theme-contrast/contrast-markdown-small.png), [contrast-info-large](../evidence/dev084/theme-contrast/contrast-info-large.png) | Supplemental host-theme launch; primary workflows use plain application entry | PASS  |
| D04 | A long source → Workspaces after change/reopen | Original scientific Workspace remains; clean duplicate has none | [source-workspace-real](../evidence/dev084/operator-final/source-workspace-real.png), [clone-workspaces-empty](../evidence/dev084/operator-final/clone-workspaces-empty.png) | Scientific source/import/export inventories and source creator checked in operator-audit.json | PASS  |

## Publication and acceptance boundary

Publication adds one immutable dev084 archive/expanded pair, active and alias copies,
dev084 compressed restore point, and retained dev083 active backup. Publisher verification
checks archive SHA/internal inventory/tree parity and protected historic releases,
external plugins and Session Generators. Fresh installed plain-entry operation and
readback follow publication and are linked in the versioned handoff. Exact changed files
are in DEV084_CHANGED_FILES.json; screenshots, coordinate journals and public readbacks
are in docs/evidence/dev084. All requested supported GUI operations passed the recorded
operator campaign; unsupported operations have explicit SKIP rows. Manual acceptance
of corrective dev084 and earlier unaccepted behavior remains solely the user's decision.
