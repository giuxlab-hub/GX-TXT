# PCB source snapshot inspector

Version0.1.0 is an experimental import-and-inspection tool for the approved
BabyBuck5V EAGLE board and its paired schematic.

Open a writable Session and launch PCB source snapshot inspector from Viewers.
Choose **Import pair…**, select the approved board `.brd`, then its paired
schematic `.sch`. Observe the operation status before using a result. **Cancel
import** requests cancellation; wait for the resulting terminal status.

Use **Refresh** to list completed canonical source snapshots. Select a completed
snapshot and choose **Inspect** to consult its recorded source information.
Import does not begin merely by opening this Viewer.

A committed snapshot retains source identities, hashes and licensing information
through the framework Document and Resource owners. `COMMITTED` denotes a
completed commit. `COMMITTED_DISPLAY_UNAVAILABLE` means the commit completed but
its immediate display was unavailable. `OUTCOME_UNKNOWN` requires reconciliation;
do not infer either success or absence from that status.

This partial development tool covers fixed-pair source snapshots. General CAD
editing, native PCB projection, physical3D, circuit solving and signal-integrity
analysis remain outside its current qualified scope. Source/declaration admission
is verified; real canonical import, Resource reopening, GUI interaction and
lifetime acceptance remain pending. Preserve the original files and consult the
release's scoped acceptance record before treating an experimental result as
scientific evidence.

SPDX-License-Identifier: GPL-3.0-or-later
