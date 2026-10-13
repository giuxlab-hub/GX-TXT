# GX-TXT Python Script 1.1.0

The dedicated Python Script Workspace Viewer edits registered `.py` scripts in User or Session scope. It uses CORE Script Registry, Script Execution, and resource lifecycle; it remains separate from Octave Script Workspace.

`analysis.python_script` is a normal installable GX-TXT Analysis module. It
selects a registered Session Python script by stable `session:<id>` reference.
CORE Script Execution verifies its source hash, runs an exact snapshot using
configured `runtime.python`, and records the runtime, script revision and API
requirements with the Session. The same Script Library and Session Script
Explorer serve Octave and Python.

See [the shared scripting guide](../../../docs/help/scripting.md) and
[the Python client reference](../../../docs/api/PYTHON_SCRIPT_CLIENT_v1.md).
