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

Import preserves the RAW source and runs the existing streaming Octave worker.
Each enabled signal becomes a canonical `timeseries.table` Dataset with
`time_s` and the selected signal variable. CORE owns the Dataset registry,
transaction, provenance, and source hashes. Import does not create an
Instrument record automatically. Add the actual oscilloscope in
Instrumentation when instrument provenance is needed.

Requires GX-TXT 0.9.8.10-dev and the configured GNU Octave runtime. The
package uses Acquisition Handler Plugin API v1, Configuration API v1, and
Plugin Install API v1. No Acquisition CORE redesign is required.
