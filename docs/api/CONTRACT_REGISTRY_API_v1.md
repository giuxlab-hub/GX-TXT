# GX-TXT Contract Registry API v1

Introduced in GX-TXT Pipeline v0.8.2.

## Purpose

The Contract Registry gives the framework a single discoverable view of dataset contracts used by installed plugins. It does not replace the Canonical Dataset API: it documents and exposes the contract IDs that datasets advertise through their `kind` field.

A contract answers **what structural/logical contract a dataset satisfies**. A dataset ID answers **which dataset it is**.

Example:

```text
Dataset ID: reactor.electrical
Contract:   timeseries.table
```

## Discovery

The registry is rebuilt from the installed Module API descriptors.

Existing declarations are consumed without changing Module API v1:

```ini
[inputs]
contracts=timeseries.table

[outputs]
datasets=table.generic
```

The framework records:

- contracts accepted by modules (`[inputs] contracts=`);
- contracts produced by modules (`[outputs] datasets=`);
- built-in framework contracts;
- optional explicit provider declarations.

Optional forward-compatible plugin declaration:

```ini
[contracts]
provided=spectrum.table

[contract.spectrum.table]
description=Spectral table with one spectral coordinate and one or more signals.
```

This declaration is optional. Existing plugins do not need to be changed merely to appear in the registry: their input/output declarations are sufficient.

## Core contract IDs in v0.8.2

```text
raw.csv
curve_family.table
table.generic
timeseries.table
```

The installed plugin set may add more IDs.

## Public Tcl API

```tcl
::GX::refreshContractRegistry
::GX::contractRegistryIds
::GX::contractRegistryKnown <contract-id>
::GX::contractRegistryField <contract-id> <field> ?default?
::GX::contractRegistryChoices
```

Fields currently exposed include:

```text
id
description
providers
producers
consumers
```

## Unknown/custom contracts

The registry is deliberately **not a closed enum**.

The Generic CSV importer always exposes:

```text
Other...
```

Selecting `Other...` enables a literal custom contract value. This is required for:

- plugins that do not declare their contract correctly;
- future plugins not yet known to the current framework;
- vendor/project-specific contracts;
- opening old sessions whose provider plugin is no longer installed.

Unknown values are persisted unchanged. The framework must never silently replace or delete them.

## Activation state

The registry is based on installed descriptors so a contract used by a saved session does not disappear merely because a plugin is disabled. The registry dialog also reports whether related modules are currently active or merely installed.

## Compatibility

Contract Registry API v1 is additive. It does not remove or rename:

- Module API v1;
- Canonical Dataset API v1;
- Instrument Module API v1;
- Graph Provider API v1;
- Scientific Analysis Definition API v1;
- Mathematical Model API v1.

## v0.9.4 additive contract specialization

A contract provider may declare one or more parent contracts:

```ini
[contracts]
provided=spectrum.table

[contract.spectrum.table]
description=Canonical spectrum table.
parents=table.generic
```

`parent=` is accepted as a singular alias for `parents=`. Parent relationships are transitive. The framework-owned compatibility test is therefore structural rather than a literal string equality test:

```tcl
::GX::contractSatisfies spectrum.table table.generic
::GX::contractSatisfiesAny spectrum.table {table.generic;timeseries.table}
```

Built-in relationships are:

```text
timeseries.table   -> table.generic
curve_family.table -> table.generic
```

Unknown/custom contracts remain exact-match only unless an installed provider declares their parent relationship. This preserves old sessions and avoids guessing semantics from contract names. Dataset selection, Analysis Source Map validation and standard module runtime validation all use the same compatibility relation.

Fields exposed by `contractRegistryField` now also include `parents`.

## Core frequency-domain contract (v0.9.4.1)

`spectrum.table` is now a framework-provided contract with parent `table.generic`. Its independent variable represents frequency, normally in canonical `Hz`. See `SPECTRUM_TABLE_CONTRACT_v1.md`.

## Script Bridge operations (GX-TXT dev-037)

This binding is read-only. The registry is built from installed module descriptors; `field` accepts an optional default, which is the empty string when omitted. `satisfies_any` accepts a list of expected contract IDs. Boolean results are numeric 0 or 1. Both Octave/MATLAB and Python call these names through `gxtxt_api_call(API_ID, operation, arguments)`. Arguments are positional and are passed to the named public Tcl procedure.

| Script operation | Public Tcl mapping | Positional arguments | Result |
| --- | --- | --- | --- |
| `list` | `::GX::contractRegistryIds` | none | cell of IDs |
| `known` | `::GX::contractRegistryKnown` | `contract_id` | integer `0` or `1` |
| `field` | `::GX::contractRegistryField` | `contract_id`, `field`, `default` (optional) | field value |
| `choices` | `::GX::contractRegistryChoices` | none | cell of choices |
| `satisfies` | `::GX::contractSatisfies` | `actual`, `expected` | integer `0` or `1` |
| `satisfies_any` | `::GX::contractSatisfiesAny` | `actual`, `expected` | integer `0` or `1` |

`refreshContractRegistry` is a host catalog lifecycle operation. Nested Tcl dictionaries and lists are converted recursively for script clients.
