# GX-TXT 0.9.8.10-dev-095 — Dataset XY and Script Jobs

SPDX-License-Identifier: GPL-3.0-or-later

Dataset Preview's XY Render and the independent CORE Scientific Dataset Viewer
now use independent X/Y axes. Each axis follows the selected finite scientific
values; frequency magnitude cannot enlarge PSD Y coordinates. Values, units,
ordering and gaps are unchanged. The existing bounded, ordered extrema sampler
still owns display reduction. Preview shows full source rows, drawn points and
actual view bounds. A preview is not an exact full-row scientific export.

Choose X/Y Variable IDs, then Render in Dataset Preview or Plot in Open Dataset.
The Viewer Fit control also notices changed variables, overlays and filters,
recomputing that selection; ordinary pan, wheel zoom and resize preserve the
current navigation. **Calibrated equal aspect** is an explicit optional Viewer
presentation setting. Independent axes remain the default. This control does not
convert units or alter scientific observations. Unsupported log/dB transforms
are not silently applied; an explicitly selected canonical dB variable retains
its own recorded units. Calibrated Native2D geometry/export defaults are unchanged.

Script Jobs now lists Script name first, followed by qualified Registered Script
ID, language, submitted version/revision, exact state, process start/finish,
duration and Session. Job ID remains a secondary column. Resize columns or use
the horizontal scrollbar; Copy Script ID copies the complete reference. For old
records, absent version/name fields are read from their immutable runtime, never
from the currently edited Script Registry. Missing historical fields say
"not recorded". Preparation time is distinct from actual process launch; jobs
that never launched have no invented process start or exit code.

Double-click a row (or press Enter / Open execution details) to inspect that exact
execution. Each resizable window retains its own Job ID and origin Session.
Details include frozen input aliases/Dataset IDs/revisions, Analysis Source
bindings, parameters, requested outputs versus committed publication receipts,
submitted SHA and streamed snapshot verification, actual runtime metadata,
resource policy/usage, error/result and real process exit code. Stdout and stderr
are merged in the exact retained execution log. An unavailable snapshot/log is
explicitly diagnosed. No other run is used as a fallback.

The lower manager pane is a selectable, scrollable **16 KiB log snapshot** at
selection time. List polling does not replace it each second. Terminal metadata
updates retain unchanged log text. Open details for current output or every log
byte. Read-only text supports mouse selection, Ctrl+C, Ctrl+A, context Copy,
vertical/horizontal scrollbars and adjustable pane sizes. Each details log page
contains at most 64 KiB. First/Previous/Next/Latest provide complete access;
Copy full log transfers in bounded asynchronous chunks to the clipboard (32 MiB
clipboard limit). Save full log transfers all original bytes to the chosen file
without accumulating the whole log in Tk. Large logs above the clipboard limit
remain fully available through pages and Save. This limit is reported explicitly.

Follow latest output is off by default and user-controlled for active jobs.
Manual scrolling, selection or keyboard navigation suspends following. Only an
explicit Follow action resumes it. Finished logs stay stable. Cancel, reconnect,
concurrency/resource policy and detached supervisor execution remain available.
Closing a detail window or GUI does not terminate computations.

Session Files displays trustworthy Script name/reference and state/time beside
original execution folder IDs. Horizontal scrolling preserves access to complete
captions. Open job details or double-click a run to inspect the same exact run.
Archived runs absent from the Job journal use their retained execution runtime/
report, with absent fields clearly marked. Missing/corrupt metadata retains the
technical folder ID and a diagnostic. Paths, folders, source snapshots and logs
are never renamed or rewritten to improve their display.

All validation uses independent scientific Sessions. Tutorial script04 is
excluded from execution, modification and acceptance; its known implementation
defect is not treated as a framework failure.
