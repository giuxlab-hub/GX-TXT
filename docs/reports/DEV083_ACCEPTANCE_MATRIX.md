# dev083 acceptance matrix

PASS means an executed disposable public-API or real Xorg interaction. No manual
acceptance is inferred. Portable transport and Duplicate Experiment are separate flows.

| Required outcome | Public operation / GUI | Evidence | Outcome |
| --- | --- | --- | --- |
| Default creation and old encounter | createNewSession, openSessionPath, projectDefaultId | api.log; legacy-upgrade.log | PASS; real dev082 objects retain IDs, hashes and unknown origin |
| Rename / stable row targeting / reorder / long names | projectExperimentRename; row buttons | api.log; gui.log | PASS; directory and creator unchanged |
| Same-canvas Info, type counts, modules/scripts, Markdown | projectExperimentInspect, projectExperimentDocumentRead, Session Inspection | api.log; gui.log | PASS; active Session unchanged; missing/corrupt cases explicit |
| Detach / reassignment | projectExperimentReassign, projectDetachCurrentExperiment | api.log; gui.log | PASS; Default link and Dataset hashes retained |
| Protected Default and named Project deletion | Resource Lifecycle | api.log; gui.log | PASS; members retained and reassigned |
| Session deletion / cancellation / rollback / active runtime | Resource Lifecycle and ID-bound GUI Delete | api.log; gui.log; transactions.log | PASS; recovery tree retained, exact failed/interrupted state restored |
| **Lossless Portable export/import** | projectExportExperiment, projectImportExperiment, sessionPortableExport/Import | api.log; gui.log; transport.log; portable-path.log | PASS; final external-source paths and real scientific Dataset IDs/bytes and scripts/documents retained |
| Portable collisions / unsafe paths / corrupt inventory / missing modules | existing Portable validator and diagnostics | api.log; transport.log | PASS; no overwrite/partial destination/substitution |
| **Preparation-only Duplicate Experiment** | sessionExperimentClone | api.log; regression.log | PASS; zero source Datasets/Workspaces/graphs/observations; safe profiles/preparation retained |
| A → B → clean derivative → re-export → rotate A | installationIdentityCurrent, sessionOriginRead/projectOriginRead | api.log; bridge-chain.log | PASS; creator, parent snapshot, receiving events and carrier remain distinct |
| Read-only Python / Octave identity and origin | INSTALLATION_IDENTITY_API_v1, OBJECT_ORIGIN_API_v1 | bridge-chain.log; bridge-chain/receipt.json | PASS; no ordinary serial/history setter |
| Identity issuance/race/rotation/corruption/recovery | same dev082 authority with recovery-backup correction | identity.log | PASS; 24 concurrent first starts, divergent/no-backup refusal, both interruption windows followed by primary corruption |
| Upgrade and preferences / config-only identity boundary | genuine published dev082 → dev083, configuration load and Save | legacy-upgrade.log; api.log | PASS; existing creator/IDs remain authoritative |
| Storage Profiles / real chooser roles | global and Session-private profile APIs/managers | regression.log; native-choosers.log; dev082 supplemental receipt | PASS; all five real native initial directories |
| Instrumentation / Library / unsaved decisions / Session Tools transport | existing services and native dialogs | regression-gui.log; regression.log | PASS |
| Dataset Preview | actual existing Preview GUI | preview-gui.log | PASS; cache/render/worker expiry |
| Historic Audio / Statistics | copied saved Sessions only | legacy-audio.log; legacy-statistics.log | PASS; original inventories unchanged |
| Scientific package/code preservation | 439 effective Dataset procedures, Instrument data, plugin/native/generator inventories | signatures.log; publication verifier | PASS |
| Physical devices / Windows crash behavior / exhaustive algorithm matrix | outside executed environment | technical report | SKIP; no such claim |

Original Format1 navigation/Default association is supported. Destructive deletion
keeps the prior Resource Lifecycle Format2 guard; normal explicit Save can prepare
that old format. This safety boundary does not force opening migration.

Astra: installation I01–I03/I05–I07 and Project/Session portions of I04/I08 are
implemented and demonstrated. Scientific-resource origins and all geometry/R work remain.
