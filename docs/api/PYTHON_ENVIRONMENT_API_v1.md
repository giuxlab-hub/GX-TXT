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
