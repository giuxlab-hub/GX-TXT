# Semantic Registry API v1

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in GX-TXT 0.9.7.6. Semantic roles describe what a variable means.
They are independent of Unit and Value kind. The persisted
`varN_semantic_role` string belongs to the stable, dataset-scoped
`variable_id`; it survives a missing or disabled plugin.

## Public Tcl calls

```tcl
::GX::semanticRegistryRegister particle_velocity [dict create \
    label "Particle velocity" \
    description "Velocity associated with a trajectory" \
    owner_plugin cfd.trajectory \
    allowed_value_kinds {number} \
    suggested_units {m/s cm/s} \
    aliases {particle_speed velocity_particle}]
::GX::semanticRegistryDefinition particle_velocity
::GX::semanticRegistryList
::GX::semanticRegistryByProvider cfd.trajectory
::GX::datasetVariableSemantic dataset_id variable_id
::GX::datasetVariablesBySemanticRole particle_velocity
::GX::datasetVariablesBySemanticRole particle_velocity dataset_id
```

`semanticRegistryRegister` validates a stable ID and fields. Registered
definitions are available only while their owner module is installed and
enabled. CORE definitions use an empty `owner_plugin`. The plugin's role
string in a dataset remains unchanged when its definition becomes unavailable.
Re-enabling the provider restores the definition without rewriting the dataset.
Results from `datasetVariablesBySemanticRole` include `dataset_id`,
`variable_id`, and all schema fields, including excluded variables.

Descriptor-driven modules can declare roles without Tcl code:

```ini
[semantic_roles]
ids=particle_velocity

[semantic_role.particle_velocity]
label=Particle velocity
description=Velocity associated with a trajectory
allowed_value_kinds=number
suggested_units=m/s;cm/s
aliases=particle_speed;velocity_particle
```

The descriptor's Module ID is the owner. The registry reads these declarations
during catalog loading; enable/disable affects availability immediately.
Suggested units are hints, never constraints. Unknown/custom role strings remain
valid in dataset metadata.

## Inference and explicit choices

Each variable stores `semantic_role`, `semantic_source` and
`semantic_reason`. Sources are `user`, `importer`, `plugin`, `generator`,
`inferred`, or `default`. A legacy nonempty role migrates as
`importer`; it is preserved. A blank role or GUI `Auto` uses temporal
kind/reference first, then registered name aliases, then an unambiguous unit
hint. Generic is the default if no hint is clear. The reason is shown in
Variables. A unit hint is not a scientific requirement: `ppm` may still
have any user-specified semantic role.

```tcl
::GX::datasetVariableSchemaUpdate d1 [dict create v0002 [dict create semantic_role Auto]]
# Recalculate the role and store inferred/default source and explanation.
::GX::datasetVariableSchemaUpdate d1 [dict create v0002 [dict create semantic_role particle_velocity]]
# Explicit user override, retained when other metadata changes.
```

Importers/plugins may set `semantic_source=importer|plugin` in the same public
schema update call. Registered Session Generators may declare `generator`;
public publication, transforms and portable Dataset transport preserve this
origin and its existing semantic reason. A user-selected role is not overwritten by Auto inference
when unit, name or kind later changes. The runtime variable metadata also
carries the source/reason for Octave consumers.

## Temporal semantic inference rule (GX-TXT 0.9.7.75)

Semantic meaning is not the same as representation. The CORE `elapsed_time` role therefore allows both `number` and `elapsed_time` value kinds. This supports, for example, an ordinary numeric coordinate in seconds whose scientific semantic role is explicitly elapsed time, as well as an elapsed-time-specific `hms` representation.

For an ordinary `value_kind=number`, CORE does **not** infer `elapsed_time` or `absolute_time` merely from a registered temporal alias or a temporal unit. A numeric variable named `time`, or a numeric variable whose unit is `s`, remains non-temporal unless its semantic role is explicitly supplied by the Dataset schema/importer/user. Temporal value kinds continue to use their explicit kind/reference inference path.
