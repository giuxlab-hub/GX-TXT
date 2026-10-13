# Analysis Tcl Bridge v1

The CORE `core/tcl/analysis_tcl_bridge_v1.tcl` is the supported companion process for a managed standard-Octave analysis that must call public Tcl CORE APIs. Invoke it as:

```text
tclsh analysis_tcl_bridge_v1.tcl FRAMEWORK_ROOT MODULE_RUNTIME_TCL RUNTIME_INI
```

`MODULE_RUNTIME_TCL` must be a file below the framework's `plugins/modules` directory. The bridge initializes framework defaults and the module catalog, then sources that script with `argv` containing the framework root and runtime INI path. The script can call documented public CORE APIs; it should not source the desktop entrypoint itself. The bridge does not grant access to private module files and does not change Dataset ownership semantics.

The installed `analysis.spectroscopy.ir` module is the first consumer. It uses the bridge to publish normal Session Datasets and a report before its Octave renderer creates the corresponding graph from those published results. This bridge is headless; Tk initialization is not required.
