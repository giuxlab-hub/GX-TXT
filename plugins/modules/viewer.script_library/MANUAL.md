# Script Library 1.0.4

This genuine Builder-authored compiled C++ Viewer uses the shared Script Registry,
Project, SourceSurface, parameter, SourceNote and reviewed Runner owners. It never
implements a second Registry, source store, scheduler or filesystem interface.

File provides User/Session New Script, equally visible New Project, Save, copy,
assign, source/project import and export. View provides filtering, bounded paging
and the existing language Workspace; Run provides reviewed execution and Jobs.
Source and parameter drafts remain CORE-owned. Existing canonical Save checks the
exact source/revision/full-record/namespace; cold Restore is inert until explicit
review. Metadata distinguishes static declared provided APIs from consumed APIs
and actual execution authority. Per-file Notes stay in the language Workspace.

This private candidate requires matching P033 CORE public native-client admission.
At authoring, strict Copy/Assign/Delete and the Workspace/History/close bridge may
explicitly refuse until their common owner integration is complete. Generic
headless Test is only a compiled no-owner-context smoke, never Library feature or
native acceptance. Normal installed GUI and independent gates remain mandatory.

Source-file selection requires the matching CORE source_read_valid feature. The finite CORE owner checks reads separately from canonical write admission; older CORE without this feature explicitly refuses source selection. Write checks and source authority remain unchanged.

Review registered source… in File explicitly reviews the current owner of the selected restored record while retaining local drafts. Approval does not save source. Save remains a separate guarded action. A CORE version lacking typed select.review_owner explicitly refuses the request.
