# dev095 authority, gaps and compatibility

SPDX-License-Identifier: GPL-3.0-or-later

Baseline is the accepted dev094 archive with SHA-256
b768dde274d2e606b3532b30cf52b9ab737f2fbb9901a347262a559c66d16f9b.

| Concern | Existing owner and gap | Additive implementation / compatibility |
|---|---|---|
| XY PSD viewport | Dataset Viewer built scientific scenes with Native2D's calibrated equal-aspect default. Native requested bounds were correct; effective axes were expanded. | Existing Native2D `aspect auto` on scientific consultation scenes. Explicit equal-aspect Viewer control; Native kernel/ABI and calibrated default untouched. |
| Peak reduction | Curve Source/Native2D already retain ordered X/Y bucket extrema, exact source rows and gaps. | No sampler, reader, smoothing or numerical rewrite. Full-row and bounded-display comparisons prove major peaks and independent fixture extrema. |
| Fit after selector/filter changes | Viewer Fit operated on its previous scene. | Existing scientific series request builder reused to compare current selection and reload only when changed; Native Fit otherwise. |
| Preview accounting | Public scientific Preview receipt lacked visible view bounds and combined drawn count. | Add `view_bounds`, `axis_aspect`, `displayed_points` to the existing receipt. No changed fields or stored data. |
| Frozen execution identity | Job envelope omitted version/ID/display Session name although immutable runtime had script identity. | Add captured `script_id`, `script_version`, `session_name`; legacy list projection reads immutable runtime. No journal migration or current Registry lookup. |
| Process timing | Journal `started` is supervisor preparation, not proof that a worker launched. | Add durable `launched_at` at successful guardian spawn. Existing state/timestamps remain unchanged; list shows actual launch or unavailable, details explain preparation. |
| Complete details/log | Job API had list/describe but no validated, bounded read projection. GUI directly read arbitrary recorded `log_path` and only its last 8192 bytes. | Extend the existing host-only Job API with `inspect`, `log_read`, `inspect_run`, `run_log_read`, `run_summaries`; same supervisor journal and Session run directories. No alternate log store/server, process supervisor or Script Bridge permission. |
| Session captions | Session File Explorer could only display timestamped folder basenames. | Async bounded summaries from the Script Execution inspector, guarded by exact current Session token and request generation. Captions never become path identity. |

Inspection lives in CORE Script Execution's Python helper called by the existing
Job supervisor API. Tcl public wrappers include `scriptJobInspect id`,
`scriptJobLogRead id ?offset count tail?`, `scriptExecutionInspectRun session runId`
and `scriptExecutionRunSummaries session`. GUI uses nonblocking `scriptJobAsync`.
Every response preserves stable exact run identity. Details use submitted journal
fields first and immutable runtime/report for missing fields; no current Script
Registry query can rewrite historic names/revision/SHA. Snapshot verification
streams SHA-256 in the helper process. Returned `exit_code` is the recorded real
worker return code, never a Tcl/GUI exception code. Missing legacy values remain
unknown. Committed outputs come from existing Publication receipts.

Log reads accept byte offset >= 0, count 4..262144, optional tail 0/1, and return
available/diagnostic/content/content_base64/offset/next_offset/size/eof/receipt/path.
Sequential UTF-8 boundaries retain complete codepoints; invalid retained bytes are
diagnosed and represented for text, while Save uses exact byte content. The
reader opens only fixed per-language log filenames in the canonical Session's
exact `analysis/scripts/RUN_ID`. Descriptor-relative O_NOFOLLOW traversal rejects
symlinked directories/files, hardlinks and nonregular files without blocking.
Metadata reads are bounded at 256 KiB/file. Summaries are bounded at 4096 runs and
do not verify every snapshot. All calls are host-only, not script filesystem APIs.

Host GUI owns columns, split panes, copy/page/follow controls and transient window
state. Callback guards bind window lifetime, immutable Job ID and request
sequence. Session caption callbacks additionally bind the current Session token.
Unchanged text receives no mutation; metadata edits replace only changed spans.
Log polling never focuses a widget. An explicit user click acquires keyboard
focus so disabled Tk text remains selectable/copyable.

No new public API family or CORE authority, private scientific reader, plotting
engine, persistent Job registry, log storage or Tcl rename wrapper is introduced.
Existing unrelated legacy rename chains remain intact. Plugins, Native2D geometry kernel/ABI,
Numerical models/solver and Script Bridge transport are unchanged. Windows
Supervisor/tray, remote execution and unrelated TODOs remain outside this scope.

The mandatory 524289-row local GUI guard additionally identified a 15.4-second
step in the existing 65536-row value-provider display ingestion. The canonical
CSV provider's per-row value assembly becomes expensive at that chunk size.
The existing Curve Source async owner now schedules 4096-row Table Stream steps;
its Native accumulator still processes every exact tuple in order. No provider,
reader or sampler is replaced. Source/row/bounds/gap equality and GUI heartbeat
are rechecked with the smaller scheduling boundary. This is within the assigned
large-data Preview responsiveness acceptance, not a transport redesign.

The missing-cell acceptance fixture found that Canonical CSV correctly retains
an empty token, while Native2D's numeric-column adapter rejected it before its
finite-pair policy ran. The owning adapter now maps only an empty coordinate
cell to nonfinite input, leaving canonical source cells/dtypes untouched. This
applies to floating/integer/boolean value transport without casting integer
coordinates or bypassing the existing >2^53 guard. Sampler gaps retain the exact
missing row. The canonical shared CORE adapter is rebuilt; its geometry kernel
and C ABI are unchanged. Current consumers load it through `native2DEnsure`.
Optional legacy provider binaries/packages remain unmodified, not alternative
owners of this current shared CORE behavior. Full native, exact-row/precision,
fit/Workspace/History and local GUI regressions run against the rebuilt adapter.

The combined missing-cell/family-filter guard also exposed an existing Transform
worker conversion error on an empty Tcl numeric object. Its existing typed-tuple
adapter now preserves that cell as null in the read-only view; finite predicates
recognize it as nonfinite and explicit unit conversions preserve absence. Source
payload/schema and exact row lineage remain unchanged. The existing view's
numeric-null transport remains its established NaN representation; this is not a
new reader, transformation, interpolation or scientific storage mutation.
