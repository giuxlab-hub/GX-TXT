# STDERR Diagnostics Viewer

An ordinary GPL-3.0-or-later Viewer authored through public Viewer Interface
Builder and C++17 Viewer Development. CORE owns collection, archive access,
subscriptions, clipboard publication, Save dialog and request lifetime. The
class-based native Viewer owns consultation, filtering, classification, ordering,
search highlighting and bounded retained-page navigation.

Enable or disable capture in **Configuration → Runtime → Process diagnostics**. This Viewer shows
the actual capture state, accepted/written/drop counters, queue bytes and errors;
it never changes the capture configuration. **OFF retains readable history**.
**Refresh capture status** refreshes that presentation without reading the whole
archive. Live subscriptions deliver status notifications, and unpaused following
requests bounded next pages when new written records are reported. Notifications
received while paused or during another request remain queued. Unpausing or
finishing that request resumes the existing cursor through the finite retained
tail, without clearing cached records. EOF stops following until new records
are reported; a non-advancing cursor stops with an explicit message.

**Read from oldest** starts a fresh bounded cache. **Next page** reads at most
256 records and 1 MiB of serialized archive data. Previous/next cached page
navigate the retained local pages. The cache retains at most 1024 records and
4 MiB of serialized pages; it does not load the whole archive on refresh. A
retention-expired cursor is shown explicitly; use Read from oldest to restart.
Pause stops following while preserving explicit navigation. Auto-scroll controls
the read-only multiline payload presentation.

Module, API, Viewer, Job and Process filters apply to the current retained page
and use literal fragments of actual
`origin` metadata. Empty filters accept every value, including the explicit
`unknown` value. Process means the producer's `origin.process_id`; capture PID
identifies the host collector and is shown separately. Identities are never
guessed from the active Module or Viewer. Text search ignores ASCII case over
the displayed original payload and highlights matches. Time order sorts exact
integer microsecond timestamps, with stable record IDs as tie-breakers.
Classification uses actual severity metadata and labels unknown values Other;
payload words never create invented source identities or error severity.

Select table records to inspect their multiline payloads with shared public
source-surface colour tags. Valid UTF-8 and line endings are displayed; invalid
bytes and control bytes are shown as hexadecimal escapes. The retained record's
base64 is unchanged. Table previews are bounded; selecting a record shows a
bounded full payload page with an explicit truncation notice when necessary.

**Copy selected payloads** publishes the selected payload text through CORE's
clipboard owner. Clipboard text is a UTF-8 presentation; use export to preserve
arbitrary binary payloads exactly. **Export selected originals** selects stable string record IDs.
**Export interval from page** exports up to 4096 records / 8 MiB beginning at the
current page's archive cursor. CORE prompts for a fresh destination filename and
preserves original JSONL bytes, base64 and metadata. Selection expiration and
request cancellation are explicit. The Viewer receives no arbitrary filesystem
read/write path capability. **Cancel pending request** cancels its own outstanding
archive task; normal close unsubscribes and cancels via the CORE lifetime owner.

Successful native unit checks, policy admission or package export do not imply
real GUI, installed, collector stress or scientific acceptance. Those receipts
are separate. The ordinary package includes original source/design/project,
SDK, binary, manual and build/export evidence for later review.
