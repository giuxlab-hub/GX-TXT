# GX-TXT Session File Explorer API v1

**Introduced:** GX-TXT Pipeline v0.9.0  
**Purpose:** read-only inspection of text/data files belonging to the current GX-TXT session.

The Session files workspace is intentionally **not** a general file manager.

It only traverses `currentSession` and exposes text-like files such as:

```text
.txt .csv .tsv .md .ini .log .json .yaml .yml .cfg .asc .cir .net .lib
```

Plots are intentionally excluded because GX-TXT already has the Plot display workflow.

## Public helpers

```tcl
::GX::sessionFileExplorerAllowed $path
::GX::sessionFileExplorerScan
::GX::sessionFileExplorerRead $path
::GX::sessionFileExplorerPopulate
```

Every path is resolved against the current session. The reader never allows browsing outside that session.

The GUI places **Session files** immediately before **Help**. Selecting a file in the left tree displays its text read-only on the right. Large text files are truncated to a safe preview limit rather than loaded without bound.

## dev095 Script Execution captions

Read-only run captions use bounded asynchronous Script Execution summaries,
guarded by the current Session token and generation. Names/references/state/time
come from immutable runtime/reports and a same-Session durable job when present.
Original tree IDs and paths remain unchanged; absent/corrupt metadata shows the
folder ID with a diagnostic. Open job details / double-click opens that exact
run, including archived snapshots when its journal record is absent. Directory
scanning does not follow links out of the Session. This is not a file manager.
