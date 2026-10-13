# Scientific Worksheet 1.1.1 — User guide

Scientific Worksheet is a saved calculation workbook inside a GX-TXT Session. It combines typed cells, scientific formulas, public mathematical operations, canonical Dataset snapshots, and Plot Dataset output. A bound Dataset is read into the workbook with its source identity; editing Worksheet cells never changes the source Dataset.

## Start, open, and save

1. Open a Session in GX-TXT, then choose **Viewers → Scientific Worksheet**. A new workbook opens with one sheet, **Sheet1**.
2. Enter values or bind a Session Dataset. The workbook title, formula bar, grid, sheet tabs, and status line remain visible while you work.
3. Choose **Workbook → Save** to create or update the Session Interactive Document. **Workbook → Open…** lists saved Worksheet documents in the current Session.
4. Closing the window does not save unsaved edits automatically. Use **Save** before closing or publishing a result.

The upper controls are grouped by purpose: **Workbook** for Save/Open, **Data** for binding and table preparation, **Analyze** for functions and Plot Dataset, **Edit** for cell actions, and **Calculate** for mode and recalculation scope. On a narrow window, Analyze and Calculate move to their own row. The action names and commands are the same in either layout.

## Read and edit the grid

Column letters and row numbers identify cells such as **B4**. The active cell is shown in blue, and its full stored value or formula appears beside **fx**. A pale row highlight helps locate the active cell. Fine gridlines separate cells, including empty cells. Named columns and units appear in column headings.

- Click a cell to activate it. Double-click, press **F2**, or press **Enter** to edit directly. Press **Enter** to commit or **Escape** to cancel the direct editor.
- Type in the formula bar and select **Apply Formula** to commit the active cell. Plain numeric or text values are accepted; a formula begins with an equals sign.
- Use arrow keys, Tab/Shift+Tab, Home/End, Ctrl+Home/Ctrl+End, Page Up/Down, the mouse wheel, and the scrollbars to navigate. The grid renders a 200-row window while stored cells may extend to row 1,000,000 and column ZZ.
- Drag to select a rectangular range. Shift extends from the anchor; Ctrl-click adds another range. A blue outline marks the selected range. The status line reports its cell count, numeric count, sum, and mean for selections of up to 5,000 cells.
- **Inspect Cell** shows the computed value, unit, lineage, or a detailed error. **Clear** clears the selected range. **Undo** and **Redo** work on recent edits in the current editor window.

**Ctrl+C** copies a rectangular TSV selection. **Ctrl+V** pastes TSV starting at the active cell. Formulas copied inside Worksheet adjust their relative references once for the source-to-destination offset. Select an initial formula and its destination range, then choose **Fill Down** or **Fill Right**. Pasting ordinary external TSV does not reinterpret it as a Worksheet formula relocation.

## Sheets, columns, and ranges

Sheet tabs sit below the grid. The active tab is bold and marked with a dot. Select **+** to create a sheet; **Rename…**, **Duplicate…**, and **Delete…** act on the active sheet. Deletion asks for confirmation. Sheet names use identifiers such as Calibration_2. A cross-sheet reference uses Sheet1!A1. Renaming a sheet updates its references.

**Data → Columns / Ranges…** sets a column display name and unit or defines a named rectangular range. For example, name column B Voltage and define voltages as B1:B10; a formula can then use =numeric.mean(voltages) or =Voltage[2]. Drag a heading divider to adjust a column width. Sheet order, names, formulas, bindings, and presentation survive Save/Open.

## Formulas and calculation

References can be relative (A1), fixed ($A$1), or mixed (A$1, $A1). Copy and Fill shift only relative row or column parts. Formulas support arithmetic, comparisons, parentheses, ranges (A1:B10), named ranges, named columns, cross-sheet references, and formula-safe functions. Use **Pick Reference** when composing a formula: click or drag in the grid to insert a cell or range into the formula bar. **Ctrl+Space** completes a function, range, column, or sheet name when there is a unique match.

~~~text
=B1-$J$1
=numeric.mean(B1:B10)
=numeric.mad(B1:B10)
=Sheet1!A1+$B$2
=field(signal.convolution.linear(A1:A3,B1:B2),"value_real")
~~~

Scalar results occupy one cell. A vector spills downward and a matrix spills across rows and columns. A blocked destination reports #SPILL! without overwriting an occupied cell. Blank, boolean, text, numeric, missing, Dataset-bound, and derived cells remain distinct.

**Calculate → Mode: automatic/manual** changes the calculation mode. Automatic recalculates after edits. Manual leaves cached results until **Selection**, **Sheet**, or **Workbook** recalculation is selected. Guided operation definitions retain their inputs, options, result field, and destination for recalculation. The calculation mode is saved with the workbook.

The formula parser accepts only its documented data grammar. It does not evaluate Tcl, Octave, Python, shell commands, callbacks, or macros. The vector, matrix, complex, record, empty, and field helpers construct data-only operands and inspect structured scientific results.

## Bind a Session Dataset

Choose **Data → Bind Dataset…**. The dialog displays the Session Dataset selector and its canonical variables with names, stable IDs, kinds, units, and roles. Select one or more variables with Ctrl/Shift; choose a first destination column, first row, optional Dataset Selection ID, and a row limit. Select **Bind Selected Variables**. The dialog also exposes **Manual column mapping…** for existing A=variable_id B=variable_id workflows.

The import reads public Table Stream chunks and is limited to **20,000 rows per binding**. Numeric and text variables may be bound together. Each bound cell keeps the source Dataset ID, variable ID, source-row ordinal, optional Selection ID, unit, and original source value. Binding creates a snapshot; bind again explicitly to refresh from a changed Dataset. The source bytes and canonical Dataset are unchanged.

**Data → Convert Unit…** converts selected numeric cells through a compatible public Unit Registry relationship. No formula or Dataset import silently converts units. Undefined, ambiguous, or nonlinear conversions are refused. Incompatible unit arithmetic reports #UNIT!; undefined derived units remain blank.

**Data → Sort / Filter…** sorts one or two columns, filters numeric or text values, shows all rows, and restores source order. These actions affect only the Worksheet snapshot. Source-row lineage moves with each value and remains available after restoring order.

## Find and apply scientific operations

Choose **Analyze → Functions…**. Search by operation name or subject, browse categories, and select an operation. The lower pane shows its public provider, signature, argument information, shape, units, result fields, Worksheet example, and whether it is a formula or guided operation. The visible result count updates as you search.

For a formula-safe operation, select **Insert into formula** and supply its arguments in the formula bar. For a guided operation, select **Apply…**. Enter cells, ranges, literals, options, or a provider-owned declarative model as requested. **Preview fields** evaluates the operation and lists available result fields. Choose a field and an output cell, then select **Apply to cells**. A vector or matrix field occupies a destination range, with collision checks. The Worksheet calls public Numeric, Signal, RF Network, or Magnetics providers; it implements no new mathematics.

The Numeric foundation dispatcher and configure_fft_threads process setting are not cell calculations. Individual foundation actions are listed separately. Callback mathematics are available only through provider-owned safe declarative models. A full operation inventory appears in Task 005's WORKSHEET_MATH_OPERATION_INVENTORY.tsv.

## Preview, retain, and publish

Choose **Analyze → Plot / Publish…**. Supply an X column, one or more Y columns, first and last row, and an output Dataset ID. A Z column enables a three-dimensional preview or retained graph where appropriate.

- **Preview Graph** creates a temporary Plot Dataset graph without publishing a Dataset.
- **Publish Dataset** creates a canonical Session Dataset. It becomes available to Dataset Preview, Analysis selectors, Table Stream, and other viewers.
- **Publish + Retain Graph** publishes the Dataset and saves a Plot Dataset graph that can be reopened later.

Save the workbook before publication. Published provenance includes the Worksheet document and revision, formulas, selected rows, units, source Dataset and variable identity, and row lineage. All rendering and retained graph state use public PLOT_DATASET_API_v3.

## Common errors and recovery

An invalid formula shows a syntax location; select **Inspect Cell** for the full diagnostic. #CIRC! means cells depend on each other in a cycle. #REF! means a referenced cell, sheet, or range is unavailable. #UNIT! indicates incompatible units or a conversion that cannot be safely defined. #SPILL! means a vector or matrix destination is occupied; clear it or choose another output cell. #VALUE! covers unsupported values, shapes, or operation arguments. The status line and error dialog identify the failing action, and the saved source/formula remains available for correction. Use Undo when an edit produced an unwanted result.

Very large sources should be bound in explicit intervals. The visible grid uses a 200-row window, a single bind action is limited to 20,000 rows, and a formula range or guided output is limited to 20,000 cells. Worksheet is a scientific workbook, not an office-suite formatter or arbitrary scripting environment.

## Worked examples

### Real statistics Session

Open demo_numeric_statistics_1.0.0 on a disposable copy. Bind statistics.source variables v0001, v0002, and v0003 into A:C for 10 rows. In **Functions**, select numeric.statistics, enter B1:B10, preview fields, choose mean, and apply at J1. The real-source mean is **2.9**. Enter =B1-$J$1 in F1, select F1:F10, and choose **Fill Down**. F10 uses =B10-$J$1 and evaluates to **10.1**. Preview A versus B in **Plot / Publish**, then save the workbook.

### Interpolation or regression source

Open copied interpolation-demo and bind interpolation.source X/Y variables into A:B. Use numeric.interpolate in the guided browser with source X, source Y, and a target range, then choose its yq result field. In copied linear-regression-example, bind linear.source X/Y into A:B, apply numeric.linear_regression, and place slope/intercept in cells. A fitted column can use fixed coefficient references such as =$J$2+$J$1*A1 followed by Fill Down.

### Mixed text and numeric Dataset

Open copied uvvis_mxene_quantitative_analysis. Bind mxene.concentration.family variables member_id, parameter_value, spectral_x, and spectral_y into A:D. Column A contains text; C retains its **nm** unit; every row retains its source ordinal. Sort or filter a Worksheet range, inspect lineage, then choose **Restore order**. Derived formulas and guided statistics can use the numeric columns without changing the source Dataset.

## Final production GUI images

**Wide layout on the copied statistics Session**

![Wide statistics workbook](docs/images/worksheet_statistics_final.png)

**Narrow layout with wrapped controls**

![Narrow workbook layout](docs/images/worksheet_statistics_narrow.png)
- [Dataset binding dialog](docs/images/bind_statistics_source.png)
- [Function Browser](docs/images/worksheet_function_browser.png)
- [Guided statistics dialog](docs/images/worksheet_guided_statistics.png)
- [Mixed text and numeric source](docs/images/worksheet_mixed_text_numeric.png)
- [Real Plot Dataset preview](docs/images/worksheet_real_plot.png)
