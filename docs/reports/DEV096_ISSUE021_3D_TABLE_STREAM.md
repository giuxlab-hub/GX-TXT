# ISSUE-021 — provider-neutral 3D Dataset reads (development evidence)

SPDX-License-Identifier: GPL-3.0-or-later

This report describes the bounded HDF5 fix and its executed extracted-package
acceptance. Overall delivery is certified separately by the archive-bound gate
and publication receipts. The user accepts the existing 536-row Builder fixture;
a separately named Eridiana identity is not a release requirement.

The focused tests use private Session copies. The original 68-file STFT snapshot
is byte-identical. The user separately confirmed intentional original Workspace
edits; both prior retained curves, the complete 73-step History prefix and all
recorded Dataset payloads remain exact. See `DEV096_SCIENTIFIC_INTEGRITY.md` and
the retained initial audit plus user-confirmation receipt. The later Workspace
state is preserved rather than overwritten with the initial snapshot.

## Executed cause and corrected boundary

The official accepted dev095 archive SHA-256 is
`95e93f9b5f69238205a269ec764facb1bef13e336c9ca4819925ae11bae5e3fe`.
The unchanged guide Steps 1–3 ran as normal public Script Jobs in a fresh
disposable Session. Step 3 failed with the reported invalid UTF-8 error after
its 2D plot succeeded. The durable error stack reaches `gxtxt_csv_split_line`
through CSV-only `gxtxt_table_stream_open_numeric_fast` / `open` from
`pd_prepare_3d_gridded_stream`. HDF5 binary data was passed to a text CSV reader.

The corrected product files are limited to the existing Plot Dataset runtime:

- `pd_runtime_info.m` carries `runtime.session` and canonical bound Variable IDs.
- `pd_prepare_3d.m` uses `gxtxt_table_stream_open_dataset` in both scattered
  passes, preserving line3/scatter3/trisurf policies and original row identities.
- `pd_prepare_3d_gridded_stream.m` uses the same public v3 source contract in
  grid-axis scan and grid-load passes. Progress reports canonical row offsets;
  both streams close through `unwind_protect`, including validation failures.
- `pd_3d_family_values.m` formats already-streamed typed Family values for the
  existing grouping policy. Exact int64 keys beyond double precision stay
  distinct. It is not a Dataset reader or storage provider.

There is no HDF5-to-CSV fallback, second reader, new PlotSpec field, new public
plot operation or change to unrelated plotting modules in this fix. The separate
authorized Builder work has its own additive selected-row PlotSpec extension;
that extension is not part of ISSUE-021. Existing gridded rejection/reduction
semantics remain in their original owners. Prepared groups now retain the
original zero-based source rows aligned with displayed XYZ/grid cells.

## Focused evidence actually executed

Paths below are relative to `_evidence_integrated_dev096` in the development
workspace; failed earlier harness logs are retained alongside successful runs.

| Evidence | Executed result |
| --- | --- |
| `stft-021-baseline/step-3.log` | Accepted dev095 failure stack reproduced; Steps 1/2 completed and all five scientific payload hashes preserved. |
| `stft-021-candidate.log` | Unchanged Steps 1–3 all completed through public Registry/Job/Bridge; Step 3 approximately 19.799 s. |
| `stft-021-gui3d3.log` | Real Xorg :1 saved surface/native 3D rotation/reset/reopen, stable units, worker reuse and owned cleanup. |
| `stft-021-gui2d1.log` | Existing HDF5 2D saved graph, native enlargement and unchanged science. |
| `stft-021-real-user-copy-gui.log` | A fresh copy of the actual user's STFT Session opened and rendered; source hashes unchanged. The original Session was not rendered or modified. |
| `stft-021-matrix1-resume3.log` | All seven 3D subtypes on genuine equivalent CSV/HDF5 XYZ, optional Family/Color, exact grid/scattered mapping, malformed grids, reductions and persistent Variant reopen. |
| `stft-021-cancel1.log` | Public Job cancellation while its owned HDF5 v3 bridge was active; six captured owned process identities gone, every source hash preserved. |
| `stft-independent-hdf.json` | Independent h5py read matches every one of 8,385 XYZ values against the canonical v3 reference; source SHA before/after unchanged. |
| `stft-021-types4.log` | Float32 grids across all seven 3D types and implicit-coordinate line3/scatter3/trisurf pass exact values/row maps/units/schema checks on both CSV and HDF5; all four original payload hashes unchanged. |

The actual guide grid is 129 frequencies × 65 times (8,385 rows), X 0–16 s,
Y 0–4096 Hz, Z approximately −99.30487 to −15.44006 dB. The separate complex
matrix is 2048×513. Independent reconstruction RMSE is
`1.497736388085181e-16 V`; it is not inferred from a rendered image.

The numerical matrix checks every prepared XYZ and original row identity against
the independent reference, not just corners. Additional formula controls include
two Unicode Families, explicit Color, axes with different display names and
stable canonical IDs, and two distinct int64 Families at 2^53 and 2^53+1.
Duplicate/missing/nonfinite grid cases reject rather than inventing cells;
scattered nonfinite rows follow their existing drop policy. Chunks 1/7/65536
produce identical retained values. An invalid Session fails with bridge cleanup.

The large HDF5 control has 263,425 rows (1025×257). Direct preparation measured
8.541315/8.588583/8.557735/8.583244 s for none/auto/stride/minmax respectively,
retaining 263,425/1,054/1,054/1,054 displayed points. Peak Octave VmHWM was
80,220 KiB. Progress was observed at canonical 65,536-row boundaries through
263,425/263,425; these are process measurements, not whole-desktop memory.
Resume entries with render time 0–1 ms only confirm reuse of an already valid
artifact and are explicitly not fresh render benchmarks.

## Remaining integrated work

The shared Viewer/Fitter/Builder regression matrix, source-integrity inventories and final
archive extraction tests remain required before release. This report does not
remove ISSUE-021 or any other entry from the authoritative remaining-work TODO.


Original Workspace audit clarification: the user confirmed the observed
idoc_0004 edits as intentional. Semantic comparison preserves both old curves,
the original 73-step History prefix and every recorded Dataset payload. The
initial byte difference is documented, not undone. The confirmed inventory is
pinned separately; subsequent changes require a fresh review. This resolves the
earlier integrity question and does not change the HDF5 source-data result.
