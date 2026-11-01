# Dev080 technical handoff: policy authoring consolidation

Authoritative baseline: published/installed dev079, SHA-256 c844ed083114924ce5a7cd3ea7b01ec496e2db1649e99e985b69cfdf0e4661ed. Target 0.9.8.10-dev-080. User manually accepted dev079 Duplicate Experiment. No mass migration: 100 other bundled modules, all scientific algorithms and all old plugin packages stay byte-identical. The maintained Builder tool alone is released as 1.2.0.

## Actual API review and minimal correction

Dev079 publicly validated `config_copy=input` with `config.input.type=dataset`. The reproduced fixture also accepted variable/selection/temporal_set/table/model/analysis_definition. Dev080 reuses Standard Module types, binding roles and source/source_role metadata to reject scientific selectors irrespective of names. External-reference actions require file/path types. The worker clears scientific typed defaults before policy application, preventing an invalid/empty policy from reviving `input=old_measurement`. This is v1, not a new schema; all 3,247 existing Tcl signatures and all 439 effective Dataset procedure bodies are preserved.

Absent, invalid and unsupported policies still do not gate module installation/discovery/execution. Fallback disables selectable modules, clears Run/scientific links and resets custom settings. No new callbacks, authorities, module-ID clone branches or global release pin. Registry ownership/generation, immutable resources, inert code envelopes, scripts and dependency validation remain dev079 contracts. Source scientific ownership always overrides a declaration; scientific bindings, Datasets, Workspaces and owned History/resources, graphs and observations remain excluded.

## Representative adapter assessment

| Cases | Class | Decision |
|---|---|---|
| Python Script Registry records; Octave registered scripts; instruments | A | Existing language-independent registries; exact source bytes remain registry-owned. No module migration. |
| Dataset/Graph/Workspace registries and managed documents/resources | A | Existing authoritative identities/dependencies. No redesign. |
| `analysis.octave_script` historical `gxtxt.octave_script.document` 1.0 | C | Retain narrow inert author-code codec; no rewriting/execution or invented provenance. |
| Native3D `gxtxt.native3d.viewer_state` 1.0 | C | Retain dependency-validated structured preparation adapter. Scientific-source layers/documents omit. |
| `plot.dataset` legacy interactive scene; Curve/3D Workbench, PDF OCR and Table Extractor native Workspace schemas | A/C | Registry/global scientific exclusion plus documented historical native exclusion schemas. No conversion, reconstruction or preservation of Workspace state. |
| Generic CSV acquisition/batch paths in historical Format-2 Manifest | A/C | Preserve CORE acquisition semantics: clear known input registrations/paths, retain clean setup defaults. No arbitrary filename classifier. |
| Avoidable new module-name assumptions | B | None demonstrated beyond dev079 centralized schema adapters; no cosmetic rewrites. |
| Missing general ownership/policy capability | D | None: v1 covers authoring. Reproduced typed-selector validation gap corrected generically. |

## Standard authoring and Builder

Normative MUST applies to new/substantially updated modules owning Session-persistent state, not runtime installation. Empty minimal policies are recommended for other new modules. Legacy settings loss is intentional and accepted. Builder schema_version=1 remains unchanged and retains unknown metadata/source declaration choices and A/B/W project content. Missing duplication_policy generates only api_version=1. Optional flat public keys serialize actual module.ini sections and are validated by the installed CORE parser/validator in a headless Tcl interpreter; research source is never run by authoring validation.

The small advanced GUI editor supports Validate/Apply/Cancel for reviewed scalar/external configuration, exact document policies and owner-root preparation files. No new document ownership wizard. Full generated manuals explain reset/retention and global exclusions. Scientific script bytes are unchanged. CLI and GUI use the same contract. Capability discovery is API v1, without an exact GX-TXT release requirement; Builder package minimum dev079 documents the earliest known provider. Python tkinter/Tcl runtime is required for authoring; validation creates no Tk window.

Runnable Python/Octave examples and minimal/safe Builder projects live in examples/experiment_duplication_policy. They use gxtxt_api_call for capability/info/module/flat validation/preparation receipt and ordinary canonical data inspection; no filesystem clone or classification permissions. Tcl serialization exposes some numeric receipts as strings; examples normalize these at the language boundary. Shared CORE bridge implementations are unchanged.

## Focused acceptance scope

- Public type validation; absent/invalid/supported installed policy and hostile global exclusions.
- New out-of-tree declaration with exact preparation resource ownership; mixed/stale/deleted-resource/unknown objects and uninstall receipt compatibility; same-byte distinct ownership.
- API clone/source inventories, independent identity, Projects/collision/reservation/mid-copy/registry rollback, Save/reopen and fresh Dataset/Workspace/Graph operations.
- Genuine Builder ZIP install and deterministic rebuild; minimal and safe gain for Python and Octave; actual execution after clone with fresh Dataset and normal execution provenance.
- Untouched installed analysis.python_script, original nondefault arguments/registered script/source binding, clean fallback, explicit fresh reconfiguration and real shared queue execution. Complete source and original plugin inventories unchanged. Historical generated ZIP without policy remains installable; historic A/B JSON and schema-version-1 W project build/install without lost metadata.
- Existing Octave code documents, Python registry records, Native3D preparation/resource and scientific Workspace viewers, Dataset Publication and graph authorities covered by retained dev079 regression fixtures. Actual public headless Python and GNU Octave supported/invalid/absent policy operations and receipt pass.
- Disposable copies of real large Audio and Descriptive Statistics saved Sessions open/clone/save/reopen; originals unchanged. This is Session compatibility coverage, not a claim of running every scientific algorithm.
- Authenticated Xorg :1 input for real Builder editor/ZIP creation and Session Duplicate Experiment menu/dialog, drafts, report, Session selectors and preview; visually reviewed screenshots.
- Archive/expanded/active/alias/restore and internal SHA manifests; new Builder ZIP/expanded parity, all historical archives and independent generator/external inventories protected.

No broad scientific algorithm matrix or arbitrary undocumented third-party formats tested. An exploratory statistics-first-publication fixture encountered an output-registration error; it is not used as passing evidence. The required real legacy execution case uses untouched Python Script. No scientific/publication implementation was modified to expand this task. Only clean final passing logs are bundled; private development diagnostics remain outside the release.

Installed release checks and publication SHA are recorded in the external versioned handoff/current pointers. Manual acceptance is pending. Stop after dev080 delivery; no Phases 2/3, Workbench development or further migrations.
