# Dev104 Project organization engineering acceptance

This workstream is implemented in the isolated candidate. It is not an official
dev104 activation or acceptance of the still-required Builder, Print Studio and
complete release delivery.

Project API's existing registry holds optional organization fields. The original
Project / Experiment transaction owns all writes, preimages and recovery. The
same public guarded move handles native drag/drop and keyboard Cut/Paste. No
Session directory relocation or Dataset namespace change was introduced.
Project Portable maps new group identities instead of merging equal names.

Engineering evidence under `_private_dev104`:

- `project_contract_03`: create/rename/remove/assign, stale and foreign-group
  refusal, Default protection, no-write group reassignment, exact registry and
  memory rollback, registry reload and portable namespace remapping: PASS.
- `project_gui_06`: actual Project/namespace editors, native pointer drag/drop,
  cross-Project groups, keyboard return to Default, search and stale/invalid
  targets: PASS, no unexpected Tk errors. Scientific-copy moves preserved all
  **594 files** outside the organizational Manifest, with exact before/after
  hashes and an unchanged original private source copy.
- `project_scale_01.tcldict`: 200 additional Projects and 400 genuine empty
  Sessions created through public owners in a separate process. Fixture setup
  took 271,671 ms outside Tk; this is not a GUI latency measurement.
- `project_gui_09`: 204 Projects / 816 logical tree entries, real filtered
  results, offscreen keyboard moves, restored selection/scroll after page
  rebuild, compact/large screenshots and no background errors: PASS. Maximum
  measured event-loop gap was **96 ms** for a 10 ms heartbeat. Input generation
  is disclosed: normalized focused Tk entry events measured filtering; actual
  X11 keyboard events exercised movement separately.
- The same final GUI run exercised Rename and Remove on populated Session and
  Project namespaces through actual controls and native confirmation. Members
  remained in Ungrouped. Pointer edge autoscroll changed the viewport; cancelled
  invalid release preserved membership and generation: PASS.
- `project_crash_01`: a directly owned child was interrupted after real registry
  and Manifest writes. Normal startup recovery restored both exact preimage
  hashes, removed the journal, and a subsequent retry committed: PASS.
- `project_scientific_portable_01`: grouped scientific export/import preserved
  all **29 Dataset IDs and payload SHAs**, declared creator, and group meaning
  while assigning fresh organizational IDs. The original private source stayed
  unchanged. A genuine ungrouped dev103 package from `project_legacy_01` imported
  normally: PASS.

Retained failures are not acceptance receipts. The first GUI startup exposed
an invalid appended bind expression; the next exposed Treeview identify's
argument count. Both were fixed at the GUI owner. A drag automation attempt
released over a row shifted by hover expansion; the corrected test follows the
logical target. `project_gui_05` exposed a Configuration registration reset on
New Session; registration now belongs to normal Configuration initialization.
That run also showed expensive automatic scientific inventory inspection on
selection; the navigator now uses metadata summaries with explicit Info.
`project_gui_07` is INVALID_COMPARISON: unfocused generated key events did not
exercise filtering. Subsequent tests assert actual filtered contents and retain
the raw failed attempts.

Original acceptance evidence for unchanged scientific/portable services remains
separate. Plot Dataset, Curve Digitalizer and original scientific Sessions were
not modified. Installed dev104 acceptance and canonical delivery remain required.
