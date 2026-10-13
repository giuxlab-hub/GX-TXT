# GX-TXT Session Generator Library API v1

GX-TXT 0.9.7.71 introduces a public, domain-neutral contract for reusable Session generators and portable generator libraries.

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
```

The Library Manager is a GUI client of these operations; scientific formulas do not belong in CORE.

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

0.9.7.71 ships `GX-TXT Numerical Examples` with deterministic generators for:

- Linear Regression;
- Polynomial Fitting;
- Nonlinear Fitting;
- Interpolation;
- Calculus;
- FFT Example.

Noise-bearing examples use explicit deterministic seeds and record their ground truth in the generated Session.

## Security boundary

Imported generator code is trusted installed code, not arbitrary code executed during import. Python execution occurs only after an explicit user generation request. Descriptors cannot configure arbitrary shell commands, absolute entry paths, traversal paths or URLs.

Session Generator Library API v1 is generic and contains no CFD-, chemistry-, electronics- or teaching-specific CORE behavior.
