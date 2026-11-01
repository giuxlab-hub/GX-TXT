# Python Environment API v1

CORE uses the exact configured local Python executable for inventory, static
preflight and managed Python execution. `pythonEnvironmentCommand operation`
returns its argv; existing async requests own lifetime/timeouts. The stdlib-only
helper core/python/gxtxt_python_environment.py implements inventory, preflight
and organize; invoke with -B. No installation, upgrade or discovered-package
import occurs. Inventory reports actual interpreter/prefix/base/search-path/time,
import names separately from distribution/version metadata, origins and honest
static availability. A spec is not a guarantee of successful binary initialization.

Configuration → Scripts retains existing controls and adds a searchable bounded
inventory below them. Refresh uses that interpreter; a runtime change invalidates
pending replies and refreshes the panel. Unavailable runtime is an explicit error.

Managed Python Run and Debug freeze source, AST-check imports in the actual Job
working directory, and retain the report. Unconditional missing imports and syntax
errors stop before user code by default, including headless callers. Set the
explicit submission option import_policy=continue to accept the recorded warning;
the ordinary Runner asks before this override. Optional ImportError branches,
conditional imports, relatives and dynamic imports remain OPTIONAL/UNKNOWN rather
than falsely mandatory. Static checking never calls a package loader. Original
byte SHA and decoded source SHA are distinct where encoding normalization applies.

Edit → Manage imports opens an embedded editor Overview: search the same inventory,
select choices or type explicit import/from/alias statements, Preview, then Apply.
Existing source remains untouched until Apply. Insertion preserves shebang,
encoding cookie, module docstring, future-import ordering and ordinary import
blocks; duplicates and alias conflicts are checked. No symbols from an imported
module are guessed or executed. Apply verifies source, Session and interpreter
and creates one Undo transaction. Registry Save remains an explicit editor action.
Cancel makes no edit. Unknown/dynamic imports need human judgment, not an installer.

## Scoped import audit (P028, additive host API)

`pythonEnvironmentAuditImports request ?callback?` accepts a Tcl dictionary:

```tcl
{scope script reference user:my_script}
{scope project reference session:my_project}
{scope framework}
```

`script` automatically admits all manifest files when the selected registered
source is a Project; `project` requires a Project. References come from the actual
Script Registry. Framework scope admits `core/python` and enabled Module Catalog
roots only. It excludes validation, tests, archives, expanded distributions,
virtual environments and symlinks. Callers cannot supply paths or search roots.
This operation is user/admin host only, unavailable in a Dataset execution
context or arbitrary Script Bridge directory request. It reuses the existing
AST `analyze` and static `resolve` backend; relative Project packages use the
frozen manifest root and execution's admitted CORE Python client path.

Without callback it returns the report synchronously. GUI consumers supply
`callback response`, receive the existing managed request ID, and call
`pythonEnvironmentAuditCancel requestId` to cancel it. The response is the normal
`{ok 1 result report}` or `{ok 0 error diagnostic}` envelope. Existing ScriptJob
auxiliary request authority owns timeout (120 s), process group, output bound
(16 MiB), lifetime and cancellation. Completion revalidates source SHA/Registry
revision, current Session, interpreter path and executable SHA; stale replies
refuse. No source/dependency execution, package installation or requirements-file
write occurs. Opening Runtime or the overlay never starts a scan automatically.

Report schema `gxtxt.python_import_audit.v1` includes:

- `identity`: executable, version, prefix/base prefix, virtual-environment flag,
  effective interpreter search paths and UTC scan time;
- `scope`, `scope_identity`, `file_count`, `source_bytes`, and exact `sources`
  containing logical identity, path/root/relative file, SHA, bytes and effective
  per-file search paths;
- `imports`: module name, source file/line/column, intent, static status, actual
  origin, classification, distribution/version mapping when metadata supplies
  one, and explanation. Import names are distinct from distribution names;
  absent metadata mapping remains explicitly unknown, even for an available
  module. Package symbols may be attributes and are never guessed as packages;
- `summary` counts `AVAILABLE`, `MISSING`, `OPTIONAL`, `UNKNOWN`, `ERROR`, plus
  overall status, `complete`, `truncated` and qualification. Invalid syntax is an
  error with its source/line and prevents a complete claim. Optional, conditional
  and dynamic imports retain conservative statuses, including relative imports
  whose package context cannot be resolved.

Nested namespace packages whose static finder requires an initialized parent are
reported `UNKNOWN`; the audit neither loads the parent nor aborts the remaining
framework scan. A fully inspected scope may therefore be complete while retaining
explicitly unresolved imports. Completeness describes admitted source coverage,
not proof that every dependency initializes successfully.

Admission is bounded to 1,000 files, 4 MiB/file, 32 MiB total source, 2 MiB request
and 20,000 imports. A bounded framework walk may report truncation; it never claims
complete coverage in that case. A missing interpreter fails explicitly.

Runtime's closable in-page review consumes this public report, with exact scope,
source selection, file counts, search, availability/kind filters, both scrollbars,
source/line inspection and Refresh/Cancel. Confirmed present is green, missing
mandatory red, uncertainty/errors neutral and textual. Missing results are shown
first; Clear restores all rows. Close/Escape cancels pending review and returns
focus without changing Runtime drafts. Save an edited Python path before audit.

Interpreter identity, result status and selected source details use bounded
read-only text panes with native scrollbars. Complete paths, reasons and SHA
values remain inspectable without expanding details over the results. Result
row heights follow the actual theme font and retain a minimum visible table
area. These are GUI layout rules; normalized reports and static scan semantics
are unchanged.
The existing Configuration > Scripts inventory and Manage imports remain separate
consumers of the same backend; Manage imports also pins the exact editor file/tab.

Managed Python Project strict preflight now checks every admitted manifest source
before executing the frozen entrypoint. The explicit `import_policy=continue`
override retains its previous meaning and records the full audit report. Single
Script preflight remains compatible.
