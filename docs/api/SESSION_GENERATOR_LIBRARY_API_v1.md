# GX-TXT Session Generator Library API v1

This is the public, domain-neutral contract for reusable Session generators and portable generator libraries.

## Purpose

A Session Generator Library is a named collection of reusable generators that create ordinary GX-TXT Sessions. Generated Sessions use the normal Session directory/lifecycle and remain usable after the originating library is removed.

Typical uses include numerical examples, scientific demonstrations, teaching exercises, signal-analysis examples and future domain-specific training material.

## Persistence model

Registry/preferences use the established GX-TXT user configuration area:

```text
$XDG_CONFIG_HOME/gxtxt_pipeline/session_generator_libraries.ini
```

with the normal fallback:

```text
$HOME/.config/gxtxt_pipeline/session_generator_libraries.ini
```

Installed library contents use user data storage:

```text
$XDG_DATA_HOME/gxtxt_pipeline/session_generators/
```

with fallback:

```text
$HOME/.local/share/gxtxt_pipeline/session_generators/
```

Large generator assets and templates are never stored in the INI registry.

## Library descriptor

Every library root contains `session-generator-library.ini`:

```ini
[library]
api_version=1
library_id=org.example.training
name=Example Training
version=1.0.0
description=Reusable training Sessions.
author=Example Author
```

`library_id` is the stable identity. Display name changes do not change identity.

Generators live below `generators/` and are discovered from descriptors rather than hard-coded GUI statements.

## Generator descriptor

Every generator root contains `generator.ini`:

```ini
[generator]
api_version=1
generator_id=linear_regression
name=Linear Regression
category=Mathematics
description=Known straight-line example.
version=1.0.0
generator_type=python
entry_point=generate.py
author=Giux-Lab
tags=numerical;example
required_capabilities=Python 3;GX-TXT Session
suggested_session_name=linear-regression-example
expected_purpose=Regression fitting and parameter recovery.
files_produced=raw/linear_regression.csv; metadata/ground_truth.txt
```

`generator_id` is stable within a library. The display name is not an identity.

## Generator types

### `python`

The installed entry point is launched only after an explicit **Generate Session** action. It receives explicit argv values:

```text
--target-session PATH
--library-id ID
--generator-id ID
```

The Debian host additionally supplies read-only child environment context
`GXTXT_FRAMEWORK_ROOT`, the actual framework root executing this request.
Independent producers can resolve its public API bootstrap without guessing an
installation path or requiring a particular module implementation version.
`--target-session` remains the only generator output authority. The context does
not grant permission to modify framework contents or another Session. Standalone
generators may accept an explicit `--framework` argument instead.

No shell command is read from the descriptor and no shell interpolation is used.

### `template`

`template_source` names a relative directory inside the generator package. Its authoritative content is copied into a freshly created Session. Derived runtime/cache paths are not blindly copied.

### `hybrid`

A template is instantiated first and the Python entry point then performs deterministic generation/customization.

## Public operations

The v1 implementation exposes generic operations equivalent to:

```text
sessionGeneratorRegistryLoad
sessionGeneratorLibraryIds
sessionGeneratorLibraryInfo
sessionGeneratorListGenerators
sessionGeneratorGeneratorInfo

sessionGeneratorInstallLibrary
sessionGeneratorExportLibrary
sessionGeneratorCreateLibrary
sessionGeneratorUpdateLibraryMetadata
sessionGeneratorRemoveLibrary

sessionGeneratorImportGenerator
sessionGeneratorExportGenerator
sessionGeneratorAddGeneratorToLibrary
sessionGeneratorRemoveGenerator

sessionGeneratorGenerate
sessionGeneratorOpenSelection
```

The Library Manager is a GUI client of these operations; scientific formulas do not belong in CORE.

### Host-only installed generator selection

`::GX::sessionGeneratorOpenSelection libraryId generatorId` opens/selects the
existing ordinary Generate Session browser. It returns before the user closes
the dialog; it does not call Generate or create a Session. This is a trusted host
GUI operation, with no ordinary Script/SDK grant or URI bridge. An intentional
native documentation action can call this owner after its own source/lifetime
admission; documentation must not manipulate the generator widgets or registry.

The exact result is:

```tcl
{status opened|unavailable|busy window WINDOW_OR_EMPTY library_id ID generator_id ID reason CODE}
```

`opened` means the actual `[generator libraryId generatorId]` row is selected and
the normal description/Generate availability has been synchronized; `reason` is
empty. Other results do not promise a selected generator. No fallback to another
library or similarly named generator occurs. Invalid IDs use the existing owner
error contract: canonicalized IDs match `^[A-Za-z0-9][A-Za-z0-9._-]*$`, are
case-sensitive and have no new global128-character limit. IDs retain the owner's
existing surrounding-whitespace trimming. The directory name/display name is
not a library identity.

The operation requires the application's GUI, a configured valid Session-root
path and the actual installed, enabled, exact catalog pair. A configured root
that does not yet exist is permitted, as in ordinary New Session; this operation
does not create it. Availability uses the installed registry without bundled
initialization. Its dialog remains installed-only through every later browser
refresh and manager-hide transition. The normal menu's default initialization
policy and modal `newSessionDialog ?preferredProjectId?` behavior are unchanged.
Explicit user Import/Enable/Generate actions retain their existing owners.

An existing owned `.gxNewSession` is reused without resetting its name (including
an intentionally empty name), Project or documentation-copy fields. A different
active grab returns busy without taking it; a foreign window at the same path is
also refused. Each invocation captures its owned native window ID. If idle layout
destroys/recreates that path, it returns `unavailable/dialog_replaced` without
fitting, focusing, selecting, restoring the old name, grabbing or cleaning up the
replacement. Newly opened forms keep the normal selected generator's suggested
name policy. A reused empty name is retained through the queued selection event;
a different ordinary tree selection restores normal suggestions. Closing the
originating manual does not close the user's generator form. Application/window
destruction retains ordinary Tk ownership; this operation adds no callback, timer,
worker or independent lifetime manager.

Bounded reason codes are `gui_unavailable`, `session_root_missing`,
`session_root_invalid`, `other_modal`, `dialog_not_owned`, `registry_unavailable`,
`library_missing`, `library_disabled`, `library_unavailable`, `generator_missing`,
`selection_unavailable`, `dialog_replaced` and `ui_unavailable`. A newly created
incomplete form is closed on refusal when no other modal owner has acquired a grab; an existing
user's form is retained. Cleanup applies only to that invocation's captured
native window incarnation, never a replacement at the same path. Ordinary tree
selection
may persist the existing last-library preference through the same registry
writer. This is the normal configuration side effect; no library install/enable,
output-root creation, generator execution or scientific write is performed.

### Optional previous Experiment documentation

`sessionGeneratorGenerate libraryId generatorId sessionRoot sessionName ?copyDocumentation?`
accepts an optional boolean. Its default is `0`, preserving existing four-argument
callers. When explicitly enabled with a Session open, the four previous Experiment
notebook documents (Notes, Objective, Procedure and Observations) are copied through
the existing notebook owner. Scientific Datasets, graphs, Workspaces and module
state are not inherited. With the option off, the generator's own documentation
remains intact.

The normal New Session dialog exposes **Copy previous Experiment documentation**
for both Create and Generate Session. It is selected initially when a source
Session exists and disabled otherwise. Reopen the dialog if its source Session
changes. The existing `createNewSession name ?projectId? ?copyDocumentation?`
entry point defaults to `1`, preserving its previous notebook-copy behavior.
Invalid booleans fail before creation. Failed creation retains the existing
transaction and recovery path.

## Portable packages

A full library can be exported as one ZIP containing the library descriptor, generator descriptors, Python sources, templates and assets. A single generator can also be exported/imported independently.

Import validates the package before installation, including relative archive paths, descriptor presence, API version, stable IDs, generator type and duplicate/conflicting identities. Symbolic links are rejected. Import does not execute Python or package install scripts.

## Generation transaction

Generation uses a temporary normal Session created through `makeSession`, then:

```text
create transient Session
→ instantiate template if required
→ execute Python generator if required
→ verify required Session structure
→ write provenance
→ rename to requested target
→ open through normal openSessionPath
```

On failure the transient Session is removed and the requested completed target is not left behind.

Provenance is stored in:

```text
metadata/session_generator.ini
```

It records library ID/version, generator ID/version/type and generation timestamp. This is reproducibility metadata only; the Session does not depend on the library after generation.

## Default library

The default `GX-TXT Numerical Examples` library ships with deterministic generators for:

- Linear Regression;
- Polynomial Fitting;
- Nonlinear Fitting;
- Interpolation;
- Calculus;
- FFT Example.

Noise-bearing examples use explicit deterministic seeds and record their ground truth in the generated Session.

The library also includes `calibrated_digitizer`: an independent raster,
ordered pixel/physical references, units, calibration and quantization assumptions.
It imports no tested scientific module and embeds no completed analysis. Existing
installed libraries are preserved; the standalone generator ZIP can be imported
through the same public library operations.

## Security boundary

Imported generator code is trusted installed code, not arbitrary code executed during import. Python execution occurs only after an explicit user generation request. Descriptors cannot configure arbitrary shell commands, absolute entry paths, traversal paths or URLs.

Session Generator Library API v1 is generic and contains no CFD-, chemistry-, electronics- or teaching-specific CORE behavior.

## New Session browsing and library management

The existing **New Session → Generate Session...** dialog presents a resizable,
side-by-side library/category/generator tree and read-only description. Select a
library or category to inspect it; select a generator to enable **Generate
Session**. Generation resolves the actual current tree selection at the time of
activation. A library, category, empty selection or removed generator cannot run
an earlier selection. Session name and Location retain the ordinary New Session
meaning, including generation into a selected Project.

**Manage Libraries...** opens management in the same dialog. Libraries and their
generators remain on the left; **Details**, **Library metadata** and **Copy
generator** tabs on the right keep inspection separate from editing/copying.
Lists have horizontal and vertical scrollbars; descriptions scroll independently.
**Hide Manager / Back to browsing**, or the upper **Generate Session...** button,
returns to browsing. Browser selection, expanded categories, scroll position and
the two modes' separate splitter proportions survive these transitions. The
window retains the user's size and position. Closing starts a fresh dialog with
no active generator; it does not remove installed libraries or generated Sessions.

This remains a normal New Session dialog, with no Viewer provider, module,
restricted author project or alternative registry. It composes the same public
`UI_FIELD_API_v1` facilities used by ordinary Viewer GUI designs:

- `uiFieldComponentCreate` supplies sections/panels, native splitters, tabs,
  read-only logs, action controls, metadata entries and bounded comboboxes.
- The public table factory supplies native Treeviews and both scrollbars. The
  dialog configures their native tree presentation (`-show tree -columns {}`)
  for the existing hierarchy; `uiFieldInspectionColumnsFit` measures real names
  recursively, with a fill tree column and horizontal access to long names.
- `uiFieldControlsLayout` wraps management actions using actual control widths.
- `uiFieldWindowFit` performs shared screen fitting. Only the dialog's own mode
  and native sash ratios are retained locally; no competing layout service is
  introduced. Registry identities, generator implementations and the generation
  transaction above remain the existing authority.

The Location selector uses the shared combobox host with this dialog as its real
owning toplevel. Native keyboard traversal, disclosure navigation and independent
scrollbars remain available. These host-only presentation operations do not add
Script Bridge or restricted C++ execution capabilities.

For illustrated user steps and a short reproducible browsing/Manager check, use
[Session Generator user guide — Help edition](../session_generator_dev109/USER_GUIDE.md).
This Markdown link and its packaged PNGs use the existing Help renderer. The
separate offline HTML edition is `docs/session_generator_dev109/index.html`;
open it in a normal browser. Its original real images and provenance are retained.
MAIN remains the sole acceptance and release authority.

MAIN accepted the seven SESSION-GEN-BROWSER criteria on 2026-10-21 at unchanged
CORE source33f301. See the family acceptance matrix and provenance.
Receipt `MAIN_FAMILY_ACCEPTANCE87.json`, SHA256
`69e24c09bb11406cb7f35028f563747192607981ba7876a3c056af6edad687e8`.
Whole workstream6 and all15 release remain OPEN.
