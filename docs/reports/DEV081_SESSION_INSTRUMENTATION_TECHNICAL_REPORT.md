# GX-TXT dev081 — Session Instrumentation GUI

Baseline: verified published/installed dev080, archive SHA-256
3179698052ab5b2678d6de4513689767e72966405061136d7eb69edfd9efe49d.
Target: 0.9.8.10-dev-081. Manual acceptance pending after delivery.

## Result and scope

Instrumentation is the seventh section of the existing Session navigator; the
previous six sections retain their identities/order. The separate Instrumentation
notebook tab is forgotten after its actual frame exists. The original descriptor
editors, variables, metadata fields, enable checkbox, removal and notes callbacks
remain at their established widget paths. A left browser selects one editor in the
right scrollable canvas. View switches hide/map widgets and retain their live state.
Browser names, stable IDs and enabled states follow the existing variables via
presentation-only traces, removed/replaced across ordinary editor refreshes.

Instruments provides Add Instrument… and Open Library…. The Add dialog uses the
existing Instrument Module catalog/choice and addInstrumentFromModule service. It
selects the new instance and refuses a stale dialog after a Session change. It does
not implicitly add hardware or change descriptors. No module-specific CORE code.

The original Library UI construction is extracted into a shared widget builder with
a host and Close callback; its Edit action uses the host's selection rather than a
hardcoded window path. All Library data services are unchanged. The main application
hosts it in the right canvas while retaining the Session browser. The Library host
is outside the instrument editor's rebuild subtree, so normal association/refresh
cannot destroy it. Close returns to the previous instrument. Selection/details
survive entry Save. A responsive toolbar keeps every existing action and Close
reachable at the supported minimum width. Existing Library metadata and instrument
notes dialogs remain the original reusable editors. The Library editor gives its
notes row the expansion weight so Save remains visible; actual GUI validation
exposed the old buttons-row weighting problem.

The existing zero-argument instrumentLibraryOpenWindow GUI entry point remains
callable. In a running main GUI it returns the embedded host widget; standalone Tk
contexts retain the former window behavior. Library storage, IDs, portable entries,
explicit synchronization and historical snapshot semantics are unchanged.

Session Import/Export commands now appear first in Tools, followed by the original
provider actions. The separate Import / Export menu is removed. Tools remains
available even with no provider actions; the original commands, dialogs and portable
transport APIs are invoked directly. Configuration-only INI export/load are retained.

## Edits and Session boundaries

Ordinary fields remain bound to the existing Session instrument array; switching an
instrument, Session section or Library view does not save or discard them. Notes
remain in the existing scientific text component. Session Save includes edited
instrument notes and uses the original notes/Session writers.

Leaving a Session prompts Save/Discard/Cancel for changed instrument configuration
or notes. Saved state is compared through the established Manifest fields; historical
schemas use their loader-normalized UI baseline rather than reinterpreting old data.
Cancel retains the source and drafts. Discard applies only when the existing Session
controller really switches. A Save that fails to commit keeps the source edits and
blocks the switch. Duplicate Experiment's existing deliberate clone/open switch is
preserved, including the original Experiment draft behavior.

Notes dialogs guard Close and instrument removal. An actual Session boundary or
renumbering closes old notes callbacks so they cannot write into another instance.
Native raw multiline controls drain pending edits before editor rebuild; the load
adapter suppresses old raw controls while the established loader replaces variables.
No new persistence authority, Manifest section or scientific classification is added.
All GUI adapters are host-only; no new Script Bridge service is appropriate.

## Verification

- All 3,247 pre-existing Tcl argument/default signatures preserved (34 additive GUI
  helpers/compatibility aliases); 439 effective Dataset procedures byte-identical.
- 31 effective Instrument/Library data and Manifest/Session Persistence procedures
  byte-identical. All plugins/packages, Instrument descriptors, Native2D/Native3D,
  Workspace API, duplication worker/policy and scientific implementations protected.
- Headless existing APIs: generic/scope instances, fields, disabled flags, variable
  instrument links, Library create/update/export/import/delete, explicit identity
  sync preserving Session-specific role/notes, Save/reopen/removal and whole Session
  transport with exact original Dataset hashes.
- Real authenticated Xorg :1 mouse/keyboard: navigator, two Add actions, existing
  editors, selection and enabled state, section switching, embedded Library and
  minimum-width Close, legacy fixed-row load-before-GUI/Cancel/discard with original
  historical Manifest hashes, entry edit/Save, historical association, Close/return, notes
  drafts, native Save/Discard/Cancel boxes, actual native file dialogs, Tools Session
  ZIP export/import, Session Save/reopen and removal/callback safety. A deliberately
  noncommitting Save fixture verifies source retention on failure.
- Dev080 real Duplicate Experiment/report/Experiment draft/Session section/Preview
  regression and source Dataset byte preservation; inherited API cloning/rollback,
  safe preparation and scientific exclusions unchanged.
- Real historical Descriptive Statistics Session opened/duplicated/saved/reopened
  only in a disposable copy; complete production original inventory unchanged.
- Archive/internal/expanded/active/alias/restore parity and historical external-plugin
  and Session Generator inventories verified. Installed GUI/API checks repeat after
  publication; their receipts and final SHA are in the external versioned handoff.

Only these focused fixtures are claimed; no exhaustive hardware/type matrix,
physical acquisition or numerical algorithm campaign. No Dataset, Workspace,
Experiment, scientific module, Native2D/Native3D redesign or subsequent phases.
Stop after verified publication and handoff for manual acceptance.
