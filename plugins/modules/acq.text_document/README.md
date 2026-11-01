# Text and Source Code Import

**Plugin:** `acq.text_document` 1.2.0  
**Framework baseline:** GX-TXT DEV111-P031 for UML  
**Runtime:** framework-configured Python 3.10+, standard library only.  
**License:** GPL-3.0-or-later.

Install the ZIP with **Modules → Install plugin...**, then select **Text and
Source Code Import** in Acquisition. Add files in the ordinary source-batch
table, adjust Dataset IDs and import. Choose Destination = Dataset for one preserved canonical file per source.
Auto routes Python to the Session Script Registry; ambiguous .m files require
an explicit choice. No numerical Variables mapping is required.
Choose **Import as** Auto, Text document or Source code independently from
**Language**. A Python `.py` file can be preserved as either `document.text`
or `code.source` while retaining its detected Python language. The acquisition
bar also offers **Copy into Session** or **Keep/reference original** for RAW;
Copy remains the default. Use Dataset Metadata's **Verify RAW source...** to
check an external reference after import.

Python, Tcl, shell scripts, Octave/MATLAB, C/C++, PowerShell and other source
languages are identified from filename/extension, shebang, modeline or a small
set of content signatures. Plain text, Markdown, JSON, XML, INI and related
configuration documents are supported too. Unknown extensions and extensionless
files are accepted when they validate as text. Ambiguous languages are reported
explicitly. These hints are not syntax validation.

Original bytes, encoding, BOM, tabs and line endings are preserved in RAW and
the canonical payload. Source code is **never executed, imported, compiled or
registered as a framework plugin**. No source dependencies are followed.

Use **Variables → select the imported Dataset → Metadata...** to inspect or edit
`code.language`, detection information, encoding, line counts and your own
project metadata. Use **Language override** only when automatic classification
needs correction; it applies to every row imported in the current run. Encoding
overrides work the same way. Restore both settings to `auto` for normal mixed
batches. The pre-import Preview uses the same current Encoding and Language
settings as import.

See `MANUAL.html` for the complete workflow, language catalog, metadata schema,
encoding and preview limits. `docs/CORE_EXTRACTION.md` describes the separated,
commented components suitable for future CORE migration. the framework P031 release handoff
records independent acceptance; author checks have their own scoped receipts.

No CORE procedure is replaced. The imported Dataset preview receives the
Session path through the public Acquisition Handler callback and reads its
persisted fields with Dataset Metadata and Session Inspection APIs. No viewer
or other module is required.

P031 adds normal `.puml` / `.plantuml` acquisition as `document.uml`, parent
`document.text`. The shared CORE bounded `gxtxt.plantuml.v1` class/sequence parser
validates the entire exact UTF-8 source (4 MiB maximum). Original bytes/SHA, BOM,
line endings and RAW remain unchanged; no dummy table, Group or executable
source is created. Invalid syntax/encoding and Session-script destination refuse.
Other file suffixes keep their normal detection/import behavior. See the manual
and framework `UML_DOCUMENT_API_v1` for the exact supported subset and limits.
