# Dev107 substantive cleanup receipt

Completed two real deletion sweeps before main implementation. Independent backup was user-confirmed.

- Deleted trees: 1,600.
- Measured available-byte recovery across deletion intervals: **92,100,120,576 bytes (85.775 GiB)**.
- First interval: 40,157,663,232 → 125,277,831,168 available bytes.
- Second interval: 124,383,989,760 → 131,363,942,400 available bytes.
- Net first-before to second-after: 91,206,279,168 bytes; successor checkout and intervening evidence consumed space between intervals.
- Nominal allocated bytes removed: 92,717,776,896; this differs from actual available space because retained documentation/scripts and concurrent framework preparation consume blocks.
- All 241 registered restore files retain exact SHA-256. The actual dev106 restore archive was streamed and matched all 16,077 manifest files; canonical and active files retain exact declared bytes.
- Original monitored scientific Session: no changed files. No user process was signalled. Dev105 is reserved; accepted dev106 files remain intact.

## Deletion categories

- backup: 11,629,178,880 allocated bytes.
- baseline: 3,001,626,624 allocated bytes.
- build: 108,924,928 allocated bytes.
- dev102: 1,062,084,608 allocated bytes.
- evidence: 48,433,455,104 allocated bytes.
- private: 1,252,085,760 allocated bytes.
- release: 4,055,400,448 allocated bytes.
- staging: 5,904,216,064 allocated bytes.
- work: 17,270,804,480 allocated bytes.

## Retained large consumers and exact reasons

- `_work_numeric_v09809`: Xvfb PID 319460 still holds this cwd. No termination authorized by cleanup.
- `_work_gxtxt_dev056` and `_evidence_dev056_matrix01`: live historical GUI test PIDs 2827984, 2834604 and 2834647 retain logs, argv and mapped native libraries; untouched.
- `_release_official_dev106`, `_private_dev106`, `_work_gxtxt_dev106`: accepted baseline, reconciliation evidence and shared Git repository for successor development.
- `_work_gxtxt_dev107`, `_private_dev107`: current isolated development and bounded evidence.
- `_sessions_numeric_windows_final_v09809/occhi_sul_molo_2`: named scientific Session of unproven disposable provenance; genuine/user data exemption applies.
- `validation/`: reusable scripts explicitly retained.
- `GXTXT_DEEP_CLEANUP_20261012`: prior cleanup documentation/report and inventories, explicitly retained under the documentation exemption.
- `_dev059_local_desktop`: live Xtigervnc PID 3523761 and mounted desktop resources; excluded from deletion.
- Canonical framework/external_plugins/session_generators, production, and restore-points: authoritative distribution/recovery assets, outside disposable scratch selection.

The second pass assessed every remaining historical scratch candidate, then removed ten obsolete linked Git worktree/root copies after proving their whole detached group inactive. Historical unique test evidence was eligible and actually deleted. Documentation and reusable validation/user/example scripts were deduplicated into `preserved-docs-scripts/objects/<sha256>`; `preserved-<tree>.json` maps every original path to verified retained bytes. Existing root scripts/documentation were left in place.

## Acceptance

CLN-01 through CLN-10: PASS for the scope described above. Evidence: baseline-before/after.json, restore-before.json, original-before/after.json, plan.json, removals.json, result.json, followup.json, plan-second.json, removals-second.json, result-second.json. Every deletion has path/category/bytes/time/status; skipped live dependencies retain precise PID and reference. Active/mounted/symlink-hop roots were refused. `shutil.rmtree` never follows subordinate symlink targets.

Full dev107 feature acceptance is still pending; cleanup success does not accept any GUI feature.
