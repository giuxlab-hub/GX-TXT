# Signal Analysis Viewer

Open Viewers → Signal Analysis. Select a canonical numeric Dataset and stable
primary/paired/time Variable IDs. Display source uses the public Native2D host
with bounded display LOD; scientific computation reads every requested row.
Choose a method, review its contextual settings, then Analyze. The real managed
Job supplies status/progress and Cancel. A measured time coordinate is converted
to seconds by Unit Registry; alternatively declare a positive sample rate. A
conflicting rate, nonuniform time axis, nonfinite values or inexact wide-integer
conversion is refused rather than resampled or truncated.

The fifteen guided operations are quality/basic, auto/cross correlation,
periodogram/Welch PSD, ASD, coherence, FRF H1/H2, analytic envelope/phase/instantaneous
frequency, causal/zero-phase Butterworth low-pass and antialiasing decimation.
They call existing public Signal/Numeric implementations through Scientific
Execution and Script Jobs. The old private 16,384-row cap is absent. Managed input
has an explicit 2 GiB budget; oversized requests fail without partial science.

Analyze retains declared Job outputs. Publish result explicitly creates a new
canonical table through Dataset Publication, then a persistent native Plot v4
graph. Choose an output ID before publication; source identity is checked again.
Complex FRFs retain separate real/imaginary columns; neither is called magnitude
or phase. Unknown derived units remain blank with an explicit qualification.
Quality/basic retains a scalar summary rather than inventing a sampled curve.

Fit/zoom use the shared host. Workspace saves values, dynamic choices, source
bindings and managed Job identity; source data are not copied into UI state.
Session/source revision changes reject stale actions. Disabling the graphical
Viewer affects its GUI only; SIGNAL_ANALYSIS_VIEWER_API_v1 and SIGNAL_API_v1 remain
available to authorized callers. Tcl API: methods, submit parameters, status job,
cancel job; no GUI instance is required. The callable public numerical Signal
bridge remains the existing SIGNAL_API_v1 in Python and Octave.

The whole interface is a public Viewer Interface Builder design. Import Existing
Viewer, Save, Generate and reimport preserve the inert design and handwritten
handlers.tcl. Safe Preview does not run science. Generated runtime callbacks call
the same installed public science owners. Official release descriptors retain the
headless API declarations; a generated connector is not a new numerical engine.
See docs/reports/DEV106_ACCEPTANCE.md for measured Debian scope and remaining limits.
