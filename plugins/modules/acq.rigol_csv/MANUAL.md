For the illustrated native workflow, open **Help** on the Rigol importer row
or [the HTML tutorial](TUTORIAL.html). This Markdown file remains the technical
reference and is available through the manual host References menu.

# Rigol CSV Import

Select **Rigol oscilloscope CSV import** in Acquisition, then add the source
CSV to the standard batch table. The module previews the configured header
and eight data rows before import. The Variables table shows detected signal
columns; choose canonical names and units there. A Rigol DS1000Z source uses
the first header row for channel names and the second for units, `Start`, and
`Increment`. `Start` and `Increment` are timing metadata, not signals.

The default parser expects two header rows, a sequence number in column 1,
and comma-separated records. Change parser, delimiter, header count, column
mapping, or raw/trailing field counts in module configuration when the actual
export layout requires it. Those settings apply to both Preview and import.
An invalid or unsupported source remains a GX-TXT import failure to diagnose;
the module does not label previously supported Rigol exports as bad external
data merely because a preview could not map them.

Import preserves the exact RAW source. Each selected channel becomes an
independent full-resolution `timeseries.table` Dataset with stable Variable IDs
`v0001` (time_s, seconds) and `v0002` (signal, source-declared unit). All selected
channels form one persistent measurement Group. The normal Dataset Browser
expands/collapses it; move/export/import the whole Group, or explicitly detach a
member before moving it independently. Ordinary member Preview and Dataset ZIP
remain available. Missing unselected channels are never fabricated.

**Canonical storage** is `auto`, `hdf5` or `csv`. Auto chooses CORE HDF5 for
sources at least 8 MiB; smaller inputs use CSV. HDF5 uses the actual CORE
Publication v2 writer, numeric float64 schema, original time reconstruction and
canonical SHA. CSV writes 17 significant digits for float64 round trips. Neither
path reduces scientific samples. An unavailable requested HDF5 backend fails
normally; there is no disguised CSV or silent precision downgrade.

**CSV parser backend** is `auto`, `native` or `octave`. For HDF5, Auto uses the
installed native worker when available, otherwise the retained streaming Octave
worker. Both emit typed private numeric transport consumed by CORE; the worker
does not own HDF5 or the Dataset Registry. CSV uses Octave. Explicit Native
requires its installed binary and HDF5. Processing is currently one actual
parser worker; a global requested thread count does not claim parallel parsing.

Metadata records actual source channel/column, sample count, source time start,
increment/sample rate when present, sequence diagnostics, actual worker and stage
timings. No instrument model, trigger or missing engineering unit is invented.
Add a real oscilloscope in Instrumentation when that provenance is available.
CORE checks source identity across inspection/RAW staging, owns the transaction,
Namespace and Group, and rolls back failed publications together.

Requires compatible P028 CORE Acquisition numeric-publication/Group capabilities
on GX-TXT 0.9.8.10-dev, the configured CORE HDF5 Python dependencies for HDF5,
and GNU Octave for the retained Octave/CSV paths. The distributed Debian native
binary has its exact C++ source and build receipt in this package. Installation
uses the existing Plugin Install API. Acquisition importers are always available;
select the current importer in Acquisition.

## Progress, cancellation and Session identity (2.2.0)

The normal **Import into current Session** action keeps the GUI event loop
active while the native or Octave parser and CORE binary Publication run in
an owned auxiliary process. The Acquisition heading shows parser rows/percent,
channel publication and finalization. Percentages apply to the displayed phase;
validated channels remain pending until the whole Group commits. **Cancel import**
and the existing Stop action request cancellation of that same process group.

The selected Session is protected from other Dataset writes while the request
is active. Changing the selected Session cancels the original request; completion
never targets the newly selected Session. Source size/mtime are pinned on
admission, and worker source hashes are verified across the complete import.
Original RAW files are read only. Callback diagnostics and control envelopes are
bounded; complete numeric arrays remain in the existing Publication data path.

Cancellation waits for the owned worker to exit, then runs the existing Dataset
journal recovery before releasing the Session. The unfinished Group, its copied
RAW and its new channels roll back together; previous imported queue rows and
existing Datasets remain. A receipt enlisted in the same transaction distinguishes
a completed commit from a late cancellation. If recovery fails, the Session stays
protected and the UI reports failure for review. A crash is reconciled by existing
Dataset recovery when the Session is reopened.

Programmatic synchronous import remains synchronous with its existing Dataset-ID
return value. Additive host APIs are `acquisitionHandlerImportSourcesAsync module
session sources datasetId contract variables ?options? ?callback?` and
`acquisitionHandlerCancelAsync operation_id ?reason?`. The callback receives the
existing request-style `{ok result|error}` dictionary; successful results carry
`operation_id status session module_id dataset_ids`. Status is `completed` or
`cancelled`. These auxiliary requests do not create a second durable scientific
Job or Registry. Host Preview preparation after successful commit retains the
normal configured policy; the auxiliary worker suppresses only its own duplicate
advisory Preview preparation in process memory.

## Temporary numeric storage (2.3.0)

The importer explicitly marks its generated numeric transport as consumable.
CORE validates that these files belong to its private import staging area and
removes each file after its last successful use; shared time arrays remain until
all selected channels consume them. This reduces unnecessary temporary disk
writeback. Original RAW and canonical Datasets retain their existing integrity
checks and lifetime, including rollback of an unfinished Group.

Normal import retains one existing HDF5 channel provider at a time, the reliable
lower-memory choice from complete-import measurements. The native parser uses
one parser process. Configuration's worker count is a capacity budget and does
not imply that this parser processes CSV records in parallel.

One managed temporary workspace now serves the complete Group, with isolated
channel scopes. Existing owned recovery releases that workspace after cancellation.
Each canonical channel remains independently portable with its explicit float64
time axis; temporary shared buffers do not couple canonical Dataset lifetimes.

On the verified 141 MB, four-channel recording (three million samples/channel),
a matched shared-collector change reduced complete import 17.389489→16.012613s
(7.9%, observed1.086× throughput), with timed CPU 15.06→13.63s and identical
scientific values, inventories and own storage traffic. A whole-pipeline control
measured34.340439→28.021367s, with less CPU and temporary writeback; shared disk
pressure varied, so these measurements are not a guaranteed import duration.
Requested 1/2/4/8 worker experiments did not show reliable parallel speed gains;
normal parser, channel provider and durability flush remain serial.
# DEV111-P031 compatibility

Version2.3.1's illustrated guide, References and native HTML behavior require the
matching DEV111-P031 CORE. The package's DEV111 minimum does not encode a patch
number and does not claim the new guide workflow works on P029/P030 or older
frameworks. CSV parser/runtime bytes retain their prior scientific behavior.
