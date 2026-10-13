# Repeatable Config API v1 / Model Resource API v1

GX-TXT v0.9.2 provides a framework-owned descriptor-driven repeater/table for configuration that cannot be known statically by a module. The initial motivating use is mapping an arbitrary number of dataset parameter variables to optional uncertainty variables and independent mathematical-model plugins.

The module must not create its own table widget or model registry.

## Descriptor

```ini
[config.parameter_models]
type=table
dynamic=1
label=Parameter models
min_rows=1
columns=parameter;uncertainty;model

[config.parameter_models.parameter]
type=variable
label=Parameter column
source=primary
required=1

[config.parameter_models.uncertainty]
type=variable
label=Uncertainty column
source=primary
required=0

[config.parameter_models.model]
type=model
label=Model
required=1
```

Supported column types in API v1 are `variable`, `model`, `choice`, `string`/default entry, `integer`, and numeric `number`/`float`/`double` validation. The GUI owns Add/Remove, stable row IDs (`row1`, `row2`, ...), variable discovery from the canonical dataset, model discovery, and persistence.

## Runtime

The framework resolves each row before scientific code runs:

```ini
[repeatable_config_api]
api_version=1

[repeatable_config.parameter_models]
api_version=1
rows=row1;row2
columns=parameter;uncertainty;model

[repeatable_config.parameter_models.row1]
parameter=param_1
parameter_source=primary
parameter_dataset_id=fit.parameters
parameter_variable=param_1
parameter_unit=V
uncertainty=sigma_param_1
uncertainty_source=primary
uncertainty_dataset_id=fit.parameters
uncertainty_variable=sigma_param_1
uncertainty_unit=V
model=law.power
model_resource=model.parameter_models.row1
```

The consumer module therefore receives canonical variable identities and does not implement dataset-column or model-discovery GUI logic.

## Named model resources

Every `type=model` field is a model resource. It no longer depends on the special name `model_id`.

A model in a repeatable row is published as:

```ini
[model.parameter_models.row1]
api_version=1
id=law.power
descriptor_path=...
plugin_dir=...
function=...
script=...
param_names=a;b
param_initial=1;2
param_lower=0;0
param_upper=10;10
```

A scalar field such as `[config.transfer_law] type=model` is published as `[model.transfer_law]`.

For backward compatibility only, a scalar field literally named `model_id` continues to receive the historical `[model]` section as well.

## Model Parameters...

Every framework `type=model` selector receives a standard **Parameters...** button. Repeatable model cells receive the same button. The editor exposes the model plugin `[parameters]` contract:

- `initial`
- `lower`
- `upper`

The state is scoped to the model-resource owner (for example `parameter_models.row1`) and is persisted in Manifest Format 2. The framework validates numeric values, `lower <= upper`, and initial values against declared bounds before runtime generation.

## Manifest

Repeatable rows are stored under:

```ini
[repeatable_config.<module>.<field>]
rows=row1;row2
columns=...

[repeatable_config.<module>.<field>.row1]
...
```

Effective model parameters are stored under:

```ini
[model_parameters.<module>.<owner>]
model_id=...
names=...
initial=...
lower=...
upper=...
```

This API is additive to Module API v1 and does not change Dataset API, Analysis Source Map API, or mathematical model plugin descriptors.

## v0.9.3.1: optional model selectors and `kind` filtering

`type=model` is now fully optional when `required=0`. The framework-owned
combobox includes an empty value both for scalar fields and repeatable-table
columns, so a previously selected model can be cleared without a module-owned
widget. The blank selection is preserved in the Manifest and runtime map, and
does not create a `[model.<resource>]` section.

Model selectors can also filter discovered mathematical-model plugins by their
`[meta] kind`:

```ini
[config.parameter_models.model]
type=model
kinds=parameter_law
required=1
```

For a scalar field the syntax is identical under `[config.<key>]`. Multiple
allowed kinds use `;` (or `,`) separators. `kind=` is accepted as a singular
alias. Omitting both fields preserves the historical behaviour and lists all
discovered mathematical models.

The filter is enforced twice: the GUI lists only compatible model IDs, and
runtime validation rejects an incompatible persisted/manual value.

## Configuration draft transactions (dev094)

`repeatableConfigSnapshot module key` returns `{api_id REPEATABLE_CONFIG_API_v1
rows {{id row1 values {column value …}} …}}` from the established row/cell arrays.
`repeatableConfigValidateSnapshot module key snapshot` is pure: it enforces
stable unique row IDs, row limits, known columns, typed bounds and existing
Variable/Model choices. `repeatableConfigApplySnapshot` replaces those same
arrays and refreshes existing widgets. No additional row store or persistence
format exists. The central/local Configuration table editor stages this value;
Configuration's Session commit persists it through the existing Manifest and
rolls the arrays back if saving fails.
`repeatableConfigDefaultSnapshot module key` returns the descriptor's typed factory
rows without writing Session state. Generic Session Reset uses it and applies the
result through the existing validated snapshot/Manifest transaction.
