# Temporal Set Editor

**Available since:** GX-TXT 0.9.7.75  
**CORE resource API:** Temporal Set API v1  
**License:** GPL-3.0-or-later

## Purpose

The Temporal Set editor is the normal GUI for creating and maintaining the existing Dataset-scoped Temporal Set API v1 resources. It is part of the **Variables** workspace; it is not a separate temporal model and it does not create private analysis-module windows.

Normal workflow:

```text
Dataset
→ Variables
→ Temporal Sets...
→ create or edit a Temporal Set
→ Save
→ Analysis
→ select the Temporal Set
→ Run
```

The Dataset selector at the top of Variables remains authoritative while the stacked Temporal Sets panel is open. **Back to Variables** returns to the normal Variable Schema editor.

## Temporal Set types

GX-TXT exposes two persistent resource types.

- `window_set` describes a regular sequence of temporal windows. The compact generator is stored; generated windows are resolved by CORE and are not persisted as thousands of GUI rows.
- `segment_set` stores an ordered set of user-authored temporal intervals with stable segment IDs and optional labels.

Both types refer to an existing Dataset and an existing temporal variable by stable `dataset_id + variable_id` identity.

## Semantic meaning and representation

The editor deliberately keeps these concepts separate:

```text
semantic_role
value_kind
value_format
unit / canonical_unit
time_reference
time_origin
```

A variable is offered as a Temporal Set coordinate only when its Variable Schema explicitly declares compatible elapsed-time semantics. A numeric variable can therefore be valid when it has:

```text
semantic_role = elapsed_time
value_kind    = number
unit          = s
```

and an elapsed-time-specific source representation can also be valid, for example:

```text
semantic_role = elapsed_time
value_kind    = elapsed_time
value_format  = hms
```

The editor does **not** infer elapsed-time meaning from a name such as `time` or `time_s`, from the unit `s`, or from `value_kind` alone. `semantic_role=time` is not silently treated as `elapsed_time`.

`time_reference` and `time_origin` belong to the Dataset Variable Schema. The Temporal Set editor does not rewrite them or redefine the temporal origin.

## Elapsed-time representation and units

For `value_kind=elapsed_time`, CORE keeps the established canonical numeric elapsed-time representation in seconds. Source representation metadata is not applied a second time.

For duration entry and display, the editor enumerates compatible units from the public Unit Registry and validates/converts them through the public elapsed-time requested-unit infrastructure. It does not contain a private conversion table.

Conceptually:

```text
user value + requested unit
        ↓
Unit Registry / elapsed-time requested-unit API
        ↓
physical duration used by Temporal Set API v1
```

Changing the GUI unit converts the displayed value; it does not reinterpret the stored physical duration. Thus, where the registered units support them:

```text
500 ms = 0.5 s
90 s   = 1.5 min
1 h    = 60 min
```

Long-duration choices come from the Unit Registry. GX-TXT uses the explicit Julian-year resource `a` and its `ka`/`Ma` scale resources; the editor does not invent a generic calendar `year` alias.

## Window Set editor

A `window_set` editor provides:

```text
Label
Temporal variable
Parent Selection
Basis
Window size
Step
Duration unit (Duration basis only)
Partial window
```

### Sample basis

With **Basis = Samples**, `Window size` and `Step` are positive integer sample counts. No physical-unit conversion is performed.

Example:

```text
Basis        = Samples
Window size  = 4096
Step         = 2048
Partial      = Drop
Parent       = All dataset
```

The step is half the window size, so consecutive windows overlap by 50%.

### Duration basis

With **Basis = Duration**, window size and step are physical durations expressed in the selected requested unit.

Example:

```text
Basis        = Duration
Window size  = 500 ms
Step         = 250 ms
Partial      = Drop
Parent       = All dataset
```

The requested `ms` representation is converted through the existing Unit Registry / elapsed-time infrastructure. It does not change the Dataset variable's source unit, semantic role, canonical representation, `time_reference`, or `time_origin`.

The current Temporal Set API requires duration-generated windows to resolve to exact positive integral sample counts on a canonical uniform temporal axis. Invalid mappings are reported explicitly.

## Step and overlap

For regular windows:

```text
step < window size  → overlap
step = window size  → adjacent windows
step > window size  → gaps
```

The list panel's **Resolution summary** uses the authoritative Temporal Set resolver and reports resolved window size/step, overlap, member count, parent and partial policy. The GUI does not duplicate the resolver algorithm.

## Partial-window policy

The existing API policies are exposed directly:

- **Drop**: omit a final incomplete window.
- **Include**: include a final truncated window according to Temporal Set API v1 semantics.

No FFT-specific boundary behavior is introduced.

## Parent Selection

**Parent Selection = All dataset** means `parent_selection_id` is empty and resolution uses the complete source Dataset. No fake Dataset Selection resource named `All` is created.

Compatible existing Dataset Selection API v1 `x_range` resources are also listed. A parent Selection must refer to the same Dataset and temporal coordinate in canonical source space. Stable Selection IDs are persisted.

## Segment Set editor

A `segment_set` uses the selected temporal variable and provides one compact member table:

```text
Label          Start       End
---------------------------------
Startup        0           20
Steady         50          200
Transient      300         350
```

Use **Add segment**, **Update selected**, and **Remove segment** to edit the table. One shared display/requested unit is used for segment boundaries. The stored physical boundaries remain independent of the display unit.

Existing segment IDs are preserved during normal editing so references and order remain stable.

## Create, edit and delete

- **New Window Set...** creates a `window_set` through `temporalSetCreate`.
- **New Segment Set...** creates a `segment_set` through `temporalSetCreate`.
- **Edit...** uses `temporalSetUpdate` and preserves the stable Temporal Set ID.
- **Delete** uses `temporalSetDelete` and refreshes live module Temporal Set selectors.

All resources use the existing Temporal Set API persistence in the Session. No GUI-only registry is created.

## Persistence

A saved Temporal Set survives Session close/reopen with the same stable resource ID and physical definition. For duration sets, opening/editing with another display unit converts the displayed numbers rather than reinterpreting the stored values.

Regular windows remain compact persistent resources; resolved members are derived state rebuilt by the existing resolver.

## Analysis-module selection

Standard module fields with:

```ini
type=temporal_set
```

use the existing generic selector. Creating, updating or deleting a resource in Variables refreshes live compatible selectors through the generic Temporal Set resource refresh path.

For example, a window set created for the Dataset used by `analysis.fft_spectrum` appears in that module's Temporal Set selector when its declared type/source are compatible. FFT mathematics are not part of this editor.

## Validation and diagnostics

The editor and Temporal Set API report explicit errors for invalid state, including missing/incompatible temporal variables, non-temporal units, non-positive window values, invalid segment bounds, missing parent Selection and stale resources. The editor does not silently pick another variable or silently change a unit.

## Public infrastructure used

The editor is a GUI adapter over existing CORE facilities:

- Dataset Variable Schema API v3;
- Semantic Registry API v1;
- Unit Registry API v1;
- Elapsed Time Contract v1;
- Elapsed Time Requested-Unit API v1;
- Dataset Selection API v1;
- Temporal Set API v1;
- existing Variables workspace and standard module configuration widgets.

No Temporal Set API v2, private temporal registry, analysis-specific window model, or hidden default Temporal Set is introduced.
