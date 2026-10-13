# Unit and semantic model

SPDX-License-Identifier: GPL-3.0-or-later

```text
RAW value
   ↓ Value kind / parser (source decimal, HMS when declared)
typed numeric or text value (internal decimal point)
   ↓ Unit (how the number is expressed)
   ↓ Semantic role (what the variable means)
   ↓ Optional explicit conversion
canonical/display unit
   ↓ Module or renderer
```

These fields remain separate:

| Field | Meaning |
|---|---|
| `value_kind` | Parsing/interpretation: number, text, elapsed_time |
| `unit` | Unit of the stored value |
| `semantic_role` | Scientific meaning, independent of unit |
| `semantic_source` | user, importer, plugin, inferred, or default |
| `canonical_unit` | Optional conversion target |
| `to_canonical` / `from_canonical` | Explicit reversible relation |
| `display_label` | Presentation text, independent of canonical name |

The dataset key is `dataset_id + variable_id`. The name is an editable
legacy lookup; the ID remains stable when the name, unit, role or Use state
changes. Metadata edits never rewrite RAW. `Source decimal` interprets
serialized values, while internal numeric values always use decimal dot.

## Examples

- V ↔ mV: intrinsic prefix conversion, 1 V = 1000 mV.
- h ↔ s: intrinsic time conversion, 1 h = 3600 s.
- `value_kind=elapsed_time`: source parsing normalizes supported HMS values to canonical seconds; consumer requests for `min`, `h`, `day`, Julian year (`a`), `ka`, or `Ma` use Elapsed Time Requested-Unit API v1 and never reinterpret `source_unit`.
- °C ↔ K: CORE affine definition, K = °C + 273.15.
- mol/L: opaque molarity base symbol; no concentration-context inference.
- mmol/L → mol/L: CORE explicit scale definition, `x * 1e-3`;
  reverse `x / 1e-3`.
- ppm and pH: opaque identity units. Neither ppm→mg/L nor pH→[H+]
  occurs without an explicit scientific definition.
- custom_activity: assign `unit=custom_activity`, optionally set
  `canonical_unit=mol/L`, `to_canonical=x*2e-3`,
  `from_canonical=x/2e-3`. The unit/relationship persists on the
  variable's stable ID.
- Plugin role `particle_velocity`: register through Semantic Registry
  API v1 or `[semantic_roles]` descriptor. It can suggest m/s or cm/s
  while allowing other units.
- Plugin unit cm/s: register through Unit Registry API v1 or `[units]`
  descriptor, with `conversion_kind=scale`, `canonical_unit=m/s`,
  `scale=0.01`.
- Inferred role: Auto with a variable named `voltage` or an unambiguous
  V unit stores `semantic_source=inferred` and a visible reason.
- User override: choose another role in Variables and Save; source becomes
  `user`, protected from later unit/name-based inference.

If a role or unit provider is disabled or removed, stored strings and
variable-specific conversion fields remain. Unknown roles can still be
searched; unknown units remain valid toward themselves. Re-enabling
the provider makes its definition available again.

Use `datasetVariableSemantic` and
`datasetVariablesBySemanticRole` to query roles without relying on
column names. Use `unitRegistryDefinition`,
`datasetVariableUnitDefinition`, and Octave
`gxtxt_unit_convert` for units. See
`SEMANTIC_REGISTRY_API_v1.md`, `UNIT_REGISTRY_API_v1.md`, and `ELAPSED_TIME_REQUESTED_UNIT_API_v1.md`.
