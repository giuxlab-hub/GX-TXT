# Source parameter declarations v1

The public declaration is inert at execution and statically discovered when
source is saved or imported through the Script Registry. It never creates a
Dataset, submits a Job or mutates the Registry at runtime.

Python:

```python
from gxtxt import gxtxt_parameter_declare, gxtxt_context
gxtxt_parameter_declare('frequency', 'double', default=1000.0,
                        min=0.0, description='Frequency in Hz')
frequency = gxtxt_context()['parameters']['frequency']
```

GNU Octave:

```octave
gxtxt_parameter_declare('frequency', 'double', 'default', 1000.0, ...
                       'min', 0.0, 'description', 'Frequency in Hz');
ctx = gxtxt_context();
frequency = ctx.parameters.frequency;
```

Use the public function spelling directly. Python supports two literal positional
arguments and literal keywords. Octave supports literal name/type followed by
literal option-name/value pairs; enumerated values use a native cell array.
Types are `string`, `integer`, `double`, `number`, `boolean`, `choice`, `color`,
`path`, `file`, `command`. Options are `required`, `default`, `description`,
`values`, `min`, `max`, `alpha`, `allow_inherit`, matching existing typed UI fields.
Discovery does not evaluate expressions, imports or scientific source. Invalid,
nonliteral and duplicate declarations refuse saving with source file/line.
Project discovery covers every explicitly admitted source, including helpers.

Source declarations and editor/Library metadata share the existing canonical
parameter schema. Distinct names combine. A source name colliding with a manually
authored metadata name refuses saving; no precedence silently erases metadata.
Source-origin descriptors are regenerated from the saved source, with exact
source/composite SHA, source file and physical line. Source changes therefore
invalidate a Runner review before Job admission.

The shared Runner always offers Add parameter, even for an empty saved schema.
Invocation-only rows have typed value, Edit and Remove. They do not rewrite
Registry declarations. Effective values use the same validation and Script
Bridge in both languages. Host clients pass additive
`options.invocation_parameters`, a name-to-descriptor dictionary; duplicate saved
names refuse. `scriptExecutionParameters metadata supplied ?invocationSchema?`
validates the merged schema. `gxtxt_context()` exposes typed `parameters` and
`parameter_schema` origin/declaration provenance; the immutable runtime and Job
receipt preserve the effective schema.

Optional canonical Parameter Datasets preserve registered and invocation schema,
values, original source/revision, typed Variable IDs and Dataset revision/SHA.
`scriptParameterDatasetSave session reference supplied datasetId ?label? ?reviewed? ?invocationSchema?`
returns the normal Publication receipt. Load additionally returns
`invocation_parameters`, allowing the same Runner to reconstruct manual rows.
Loaded values remain editable. No declaration or preset Dataset is required to
supply invocation parameters or to run a registered Script.
