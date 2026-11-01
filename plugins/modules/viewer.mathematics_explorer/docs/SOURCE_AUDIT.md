# Read-only GX-TXT dev097 source audit

Date of inspection: 2026-10-14 (Europe/Rome). The only remote access channel
used was **Private_Task_Documents** with read-only operations. No remote terminal,
Remote Desktop Commander, SSH, Git mutation, build or Session modification was
performed. The new files were created exclusively in the isolated ChatGPT
artifact environment.

Read-only source tree:
`/home/giu/electronics-server/work-agent/TK_GIUXLAB/_work_gxtxt_dev097_integrated`

SHA-256 values below are the hashes reported by the read-only `read_text`
channel for the actual source records consulted. Paths are relative to the
above tree. They are **not** a release manifest and do not freeze dev097.

| Read-only reference path | SHA-256 observed |
|---|---|
| `plugins/modules/math.numeric/module.ini` | `f62546a961b828e6f9dcdf05b566a0c9d94ae428ea14c7b688054bd6191b83bf` |
| `plugins/modules/math.numeric/api/numeric_api_v1.tcl` | `78e27d514a9cd20a986d8b81a349dc86978e9ce3be9ac7438bd264b7d14d1db4` |
| `plugins/modules/math.numeric/api/operations_v1.tsv` | `7b4af990a079a3f1689fe22207fc3b5ab34505fa79200e42784252cf5c8617e6` |
| `plugins/modules/math.numeric/api/octave/gxtxt_numeric_v1.m` | `6da94c6343f59ad6cba6568ee98c7b67886be4be39d17c18f97a576ff7bfe61b` |
| `plugins/modules/math.numeric/NUMERIC_API_v1.md` | `d01140530e4f3ef215795b3599b6fbcdd3f79f81a165ba144be37f95d8b7b232` |
| `plugins/modules/analysis.dataset_expression/module.ini` | `df561613278576bf15982ed1d102be1d991d3b49d8e7212d9a59f6029b1cd61d` |
| `plugins/modules/analysis.dataset_expression/runtime/analysis_dataset_expression_main.m` | `a7aa8991a5c1002014ff48a8d53b3bfff5dd5c3fd18205d9565ac604e99d6a83` |
| `core/tcl/numeric_expression_browser_v1.tcl` | `f3d3fdf1bdd58d0aa382715f944e3b64bd59ae49eb80c6ba860d3af5691025d8` |
| `plugins/modules/demo.numeric.calculus/module.ini` | `477bfd004e6ff0ca5f6b6830bb8586656a1de98be098d74c147e5de6d6944342` |
| `plugins/modules/demo.numeric.calculus/runtime/demo_numeric_calculus_main.m` | `60ec2ba9e78da4acaa2f7814ea92b82792823474d21aa6584b3c47f04b9bb81b` |
| `plugins/modules/demo.numeric.root_finding/runtime/demo_numeric_root_finding_main.m` | `ab8dec99eaedb3a42af983ed87bb5cd4839c21b35600a75f489e1bf8f25dd3d1` |
| `plugins/modules/viewer.scientific_worksheet/module.ini` | `df633d8792064eca1aec7dd02070cdc7950ef37dfaed79be5d5d6b61765452ce` |
| `plugins/modules/viewer.scientific_worksheet/api/scientific_worksheet_api_v1.tcl` | `f346d587f1c539539f6243436b4db3dd9b1490b0f481f0a14387e2e80e82dc41` |
| `plugins/modules/viewer.scientific_worksheet/ui/worksheet_ux_v3.tcl` | `81234086a04e1339cc39ec4ffed2587a049bdae16493d9b93ac55fa6afc5c0e3` |
| `plugins/modules/plot.dataset/api/plot_dataset_api_v3.tcl` | `af7919d83161111c525407665ec5bd199ebb8487cdb54d2fdcc4067061f1eadd` |
| `plugins/modules/plot.dataset/PLOT_DATASET_API_v3.md` | `9b12c4261b0e44b3c3e07af3f2d7abc15120677b260d3cb6c941d4cd3e843544` |
| `docs/api/VIEWER_PROVIDER_API_v1.md` | `3d2042415c9cf9f4a9c858ba6bf6b0508b10391fd7509812912ad0a1352dc35a` |
| `docs/api/SCIENTIFIC_MULTIVIEW_HOST_API_v1.md` | `469dea768ccfe0db65a0e7de6180fac95fa2981910e5cd0128261bad0d9bcfcc` |
| `core/tcl/scientific_multiview_host_api_v1.tcl` | `9ca7040f67ebb5f03f1e8ebb3b43b84ef952c596b3245f7dd4e2f7dc32dec510` |
| `docs/api/INTERACTIVE_DOCUMENT_API_v1.md` | `2dd7b35ca2a0e1a0eca8848bb8d13d4ce39b9dbc6dd1a6a5aab950d3a4ce0a96` |
| `core/tcl/interactive_document_api_v1.tcl` | `380d5c3e1de339ac05f082980fea0e2ee27a5a282439e2c2b46bdb1b403db604` |
| `docs/api/DATASET_PUBLICATION_API_v2.md` | `115774de43022b526d6ce7a23b9188e0260d46b2cd8417f70c01e9dd56215566` |
| `docs/api/CANONICAL_DATASET_API_v2.md` | `53f6b54717b398c5a4103772479213240e390a88400d6185e32f599a104edcbf` |
| `docs/api/DATASET_VARIABLE_SCHEMA_API_v3.md` | `7237c8c55d4078a498fe2137fadcd99937e234a681d9c3970b070cd6ec6a7b3c` |
| `docs/api/UNIT_REGISTRY_API_v1.md` | `41bbe7df57438da56e85347befee13041d6a835c07ff88cf6172d4a4aec49edc` |
| `docs/api/SESSION_INSPECTION_API_v1.md` | `7c8185071fd9632cc5fea9822aad19a1218348aad6196c576f125614f225b304` |
| `docs/api/SESSION_WORKSPACE_API_v1.md` | `3b8c1323027000b7ca18161243875fedac704398447c9eeef1f2f9012e1de2b7` |
| `docs/api/MODULE_API_v1.md` | `260b48213a0c9b29db337c3f3ff4624169db48e05d969aa786aafe9b2cfb53c1` |

**Moving tree observation:** `plugins/modules/plot.dataset/module.ini` was read
with SHA-256 `c416135746945b6582c68c7ffdf9d5d01b0885d3bf83c2dce4ca42adc49ab0e0`
on an earlier pass and `57416664426c3db096d5c7875b9ccdba3f49b9290bd7972e8edb37eb8b70d48b`
on a later pass. This difference is direct evidence that the inspected worktree
cannot be treated as an immutable release snapshot. The public v3 facade source
was separately rechecked and retained SHA-256
`af7919d83161111c525407665ec5bd199ebb8487cdb54d2fdcc4067061f1eadd`.
Reinspect all relied-upon signatures immediately before integration.

## Existing mathematical components examined and practical limitations

- `math.numeric`: stable public data operations for vectors, interpolation,
  calculus, roots (Octave callback/model-specific), plus an operation catalog.
  **Reused** through its Tcl facade. It is not a GUI function editor.
- `analysis.dataset_expression`: controlled unit-aware expressions over
  **existing Dataset** variables, scalar bindings and a standard Octave job.
  Its actual runtime uses `gxtxt_analysis_expression_parse`, requiring an
  Analysis Source and publication configuration. That parser is not exposed as
  a standalone public in-process Viewer expression engine. Therefore it was
  not copied or called as a private service.
- `demo.numeric.calculus` / `demo.numeric.root_finding`: proof of Dataset-native
  public Numeric operations. Their actual execution is a standard Octave
  analysis-runner workflow with user Dataset and config, not a live GUI explorer.
- `viewer.scientific_worksheet`: verifies the standard `kind=viewer`,
  `activation_api`, `viewerBackendRegister` pattern, bounded safe formula
  evaluation, Session Interactive Documents and transient Plot Dataset previews.
  Its workbook cells and table UI are not a 1D function/domain explorer.
- `plot.dataset`: official PlotSpec v3 facade and transient 2D multi-curve
  renderer. **Reused** directly; no independent plotting implementation.
- `VIEWER_PROVIDER_API_v1` and Interactive Document API: approved activation,
  source/state ownership and Session-scoped persistence lifecycle.

## Conflict check

The module directory listing at inspection time contained 102 registered
module folders, including the existing six starting-point modules, but no
`viewer.mathematics_explorer` entry. This checks a directory name only, not
future module registry collisions; verify on the accepted release.
