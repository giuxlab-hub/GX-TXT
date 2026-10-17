# Scientific Workbook and Native Charts

Open the generated Session, then Session Workspaces → Scientific Worksheet and
open **Scientific Workbook and Native Charts**. The independent generator uses
public APIs and requires their declared capabilities, not a particular Worksheet
module implementation version.

Measurements contains an immutable five-row source Dataset with voltage -2..2 V
and current `2*voltage+1` mA. Source row identities remain attached to bound cells.
Calibration contains the explicit dimensionless gain 2. Column F uses cross-sheet
formulas to multiply the measured current by that gain; CORE unit arithmetic
expresses this product in canonical A (-0.006..0.010 A). The named range
`measured_response` refers to B1:B5. Text/UTF-8, a complex voltage, missing current
and numerical NaN are separate typed examples in columns C–E.

Two editable native charts belong to the Workbook. One shows the measured
current; the other shows the explicit gain-derived current. A separately retained
native v4 Graph in Plots uses the immutable `worksheet.derived` Dataset. Editing
the Workbook later does not change that publication.

Inspect units and source-row lineage, copy a formula, change the explicit gain,
recalculate, and use History/Undo to review semantic changes. Publish another
Dataset ID when retaining a new scientific result. Original source Datasets
remain unchanged. No noise, estimated uncertainty, confidence interval or physical
calibration accuracy is claimed by this deterministic teaching example.

The Session includes the registered public producer and its exact source SHA.
The library may be removed after generation without removing the Session.

SPDX-License-Identifier: GPL-3.0-or-later

## Install and generate

In Session Generator Library Manager choose Import Library and select the
`Scientific_Worksheet_Examples_1.0.0.zip` package. Select **Scientific Worksheet
Examples → Scientific Workbook and Native Charts**, choose a fresh Session
name and Generate. The existing framework owns staging, validation and final
Session installation. Existing Sessions are never overwritten.

The library is optional and independently distributed under GPL-3.0-or-later.
It requires a host exposing the declared Worksheet v1, Plot Dataset v4,
Publication v2 and Session Workspace v1 public capabilities. It neither checks
an exact module release nor reads private Workbook storage. The child producer
uses the host-provided read-only `GXTXT_FRAMEWORK_ROOT` context. For a standalone
fresh Session, invoke `generate.py --target-session PATH --framework FRAMEWORK`;
the target must already be an ordinary initialized GX-TXT Session. The Library
Manager handles this initialization automatically.
