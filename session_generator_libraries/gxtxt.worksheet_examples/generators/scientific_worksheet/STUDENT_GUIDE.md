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
