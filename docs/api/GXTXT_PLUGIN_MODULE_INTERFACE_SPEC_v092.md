# GX-TXT Plugin Module Interface Specification — v0.9.2 additions

This document lists the additive module-authoring contracts introduced in the final v0.9.2 package. All earlier Module API v1 contracts remain valid.

## New descriptor configuration types

### `type=selection`

See `DATASET_SELECTION_API_v1.md`.

### `type=table`

See `REPEATABLE_CONFIG_API_v1.md`. A repeatable table is descriptor-driven and may contain typed columns such as canonical dataset variables and mathematical model plugins.

## Mathematical models

`type=model` is a general model resource. The selected model is published under a named runtime section `[model.<config-key>]`; a model inside a repeatable table row is published under `[model.<table-key>.<row-id>]`.

The framework provides a standard **Parameters...** editor for model plugin parameter initial values and lower/upper bounds. Modules must consume the resolved runtime resource rather than implement private model-selection or parameter editors.

The historical `[model]` section remains as a compatibility alias when the configuration field is literally `model_id`.

## Session note presentation

Session `.md` files remain normal UTF-8 files. The Session files browser renders them using the shared GX-Markup engine; **Edit note...** opens source markup.

## v0.9.3.1 addendum — model selector constraints

Any standard `type=model` field may declare `required=0`; the framework then
provides a clearable empty choice. A field may also declare `kinds=` to restrict
model discovery to matching mathematical-model plugin `[meta] kind` values.
This applies equally to scalar fields and Repeatable Config API v1 model columns.
Modules must not implement private model-selector widgets to obtain these
behaviours.
