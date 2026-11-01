# dev096 authoritative TODO reconciliation

The authoritative file is the active framework's `GX-TXT_REMAINING_WORK_TODO.md`.
This release changes only its delivered-release header from095/from094 to096/from095.
Every existing unfinished item remains byte-for-byte intact. None of ISSUE-003
through ISSUE-021 was present as an unfinished body item in that authoritative
snapshot, so zero body items were removed. This avoids deleting unrelated manual
acceptance or future work merely because the release ran overlapping regressions.
Reserved NEXT-001–003 and later collected future issues are not implemented here.
The release-gate script compares the complete proposed TODO with this exact
header-only transformation before activation. The preceding095 copy survives in
the accepted archive, restore point and retained active-installation backup.
