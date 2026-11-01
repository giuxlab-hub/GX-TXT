# dev109 P0 — compiled Viewer lifecycle

Authority: user's urgent CORE instruction of 2026-10-19, additional to all 15
registered workstreams. MAIN1 is the sole authoritative integrator and release
owner; delegated CORE families retain their explicit ownership boundaries.
The dev109 architectural correction has passed scoped A–E acceptance. The
official dev108 installation is preserved; dev109 release acceptance and
deployment remain separate, unfinished gates.

## Confirmed root cause

Installed packages already distribute native/viewer.so and source/build receipts.
The old viewerDevelopmentInstalledOpen copied three source files into a temporary
project and called development Preview. Preview invoked compiler-based source
validation. Every viewerDevelopmentInvoke then submitted development run(), which
validated source again and compiled author and trusted adapter objects and linked
another viewer.so. The requested operations were applied only after that request
completed. The distributed binary was ignored. Real installed process traces
listed below establish the corrected compiler-free runtime.

## Required lifecycle and implementation scope

Development Build owns source/SDK/API admission and compilation. A persisted
artifact is reusable only while source, interface, project, SDK, adapter, policy,
compiler and actual included-header dependencies match. Preview/Test/Export reuse
that build; changed inputs require a new development build. Installed startup
checks package binary, build/source/interface correlation and current public SDK
compatibility, and executes native/viewer.so in place. It never calls source
validation/build or recreates a development project. Missing/incompatible binary
is an explicit error with no build fallback. Runtime temporary data belongs to
existing Resource Management; requests and descendants retain existing Script Job
ownership. Existing state, Workspace callback fingerprints and Session guards
remain mandatory.

The shared event mechanism must finish local presentation/tool selection before
subsequent Canvas input can observe the old tool. No Circuit-specific shortcut is
permitted. Scientific calculations and remote/long-running Jobs keep their
existing asynchronous owners. Twenty local selections and twenty atomic native
tool/Canvas pairs now demonstrate first-action correctness without interposed
status waits or authored C++ exchanges. Instrumented callback timings are not
untraced input-to-paint measurements.

## Mandatory acceptance ledger

| Requirement | State | Evidence required |
|---|---|---|
| A: normally installed Circuit, startup and >=20 interactions | scoped PASS | gui03: twenty native interactions, ten exact alternating R/C insertions; full descendant trace has zero compiler/linker attempts |
| A: immediate first-click tool operation | scoped PASS | historical ten alternating R/C pairs plus current Circuit25 twenty selections/twenty atomic tool/Canvas pairs, fifteen exact component insertions, no authored C++ exchange for local selection; independently sealed110 and MAIN120 |
| B: compiler unavailable, runtime libraries retained | scoped PASS | real compiler aliases unavailable in disposable QA namespace, runtime libraries verified byte-exact and loadable; actual installed Circuit and Library execution |
| C: Builder one build, close/reopen reuse | scoped PASS | real native F6v1, normal close/reopen/F7 and unchanged artifact identity; complete independent trace proves zero compilation outside explicit builds |
| C: source edit and explicit new build | qualified scoped PASS | real F6v2, atomic new inode, old mapping/source guard, new Open100 and controlled native Tick102; original lost OS pointer remains FAILED/unclassified; all compiler processes confined to the two F6 windows |
| D: second Builder-generated Viewer | scoped PASS | installed Library native filter/24-entry selection/normal close/reopen; same complete zero-compiler trace |
| E: focused existing Session/Workspace/scientific behavior | scoped PASS | genuine RLC4018 rows/public Numeric/fresh14 probe plus Circuit24 A→empty B→A, stale old-owner refusal, normal retirement and first fresh scientific owner; independent91 full seal/source/trace review |
| Plugin Manager verification and precise negative errors | scoped PASS | normal admission and five exact negative package copies; native Manager196 update preserves94 files/provider/foreign registry, honestly requires restart; current197 activation/mapping separately verified25 |
| Technical docs and TODO reconciliation | scoped PASS | current source/evidence reconciliation149 and MAIN159 decision; only this completed obligation removed, remaining CW/release gates retained |

No integrated release gate is accepted by this P0 correction. The original dev108
active release, archives, rollback and scientific Sessions are preserved. WIP commit
2ce9980 preserves integration progress immediately before this P0 implementation.

## Historical scoped verification carried forward

The original receipts and failures below remain preserved. Later reconciliation
`runtime_final_reconcile149/HANDOFF.md` supersedes their historical E/first-click
and Manager OPEN statements. Current installed admission/serve/compatibility
function bodies and native worker match the tested92f74e4 implementation;
whole-file equality is not asserted. Current Circuit/Library source, packaged
binary, build receipts, distributed SDK and C ABI checks also reconcile.
Development metadata-only reuse follows testedf4b5551/receipt03: source, design,
semantic callbacks and actual build/header dependencies still guard reuse.
This is explicit evidence reuse, not a fabricated new compiler-unavailable or
Builder campaign. The original failed Builder OS pointer remains failed.

WIP implementation is preserved in commit92f74e4; this is not a release.
The earlier managed native ABI contract exercised the actual distributed Circuit
and Library binaries for20 events each. Independent complete trace review found
503 attempted executions across207 terminated processes, zero compiler/linker
attempts and no parser/termination issues. This was not a GUI test, and subsequent
shared lifetime/admission refinements require their own focused verification.

Current public `pluginPackageRead` normal Circuit admission passed, followed by
five precise rejections on new private package copies: missing native binary,
invalid ELF/receipt correlation, changed source, changed installed interface and
changed distributed SDK. The entire original package remained byte-exact, managed
requests drained, no Session/Job was created, actual process exit0 and full empty
stderr were recorded. Evidence: `_private_next/compiled_package_admission01/`;
independent full process-trace review covered781 processes and8051 attempted
executions with zero compiler/linker attempts and no parser/termination issues. No rebuild
fallback was used. This is admission coverage, not GUI/install/fullP0 acceptance.

The installed compiler-unavailable GUI campaign03 completed with actual driver
exit0 and normal root destruction. Independent full trace review covered2371
terminated processes and20116 attempted executions: zero compiler/linker calls,
zero parser/termination issues, and114 read-only opens of the two actual installed
native/viewer.so paths across four genuine Viewer lifetimes. Twenty native
Circuit interactions produced five resistors and five capacitors with correct
first Canvas clicks. Circuit normal close/reopen and Library native filtering,
actual24-entry selection, normal close/reopen also passed. All156 frozen inputs,
host tools and protected library data remained exact; owned workers and process
groups were absent. MAIN inspected genuine Circuit and Library screenshots.

Evidence: `_private_next/agents/qa_document_readers/p0_runtime_gui03/` and
`P0_INSTALLED_RUNTIME_INDEPENDENT_REVIEW_03.md` (SHA caee6427126626f0a152aeb019582b442d09f000f3eb782ef80345d897a872b3).
All earlier QA namespace/configuration/device failures remain preserved. A wrong
one-row Library filter expectation is also preserved in full stderr: the genuine
query correctly returns three records sharing Cambridge origin. These scoped
passes do not accept scientific regression, the complete Circuit workflow or
the integrated release. Gesture durations include tracing and input tooling;
they are not a millisecond latency benchmark.

Builder Test C used exactly two genuine native F6 builds. Warm reopen reused the
original binary without changing its SHA/inode/mtime. An official source change
was guarded before and after the second explicit build; atomic publication kept
the old mapped inode alive. The new Preview displayed100 and a separate controlled
native Tick gesture produced102. Its original combined OS pointer failed to
reach Tk press handling and remains FAILED with unclassified delivery cause;
the later diagnostic does not retroactively pass that input. Normal root/driver
exit0, worker drain and all156 exact inputs are recorded. MAIN inspected actual
old11/new100/new102 images. Complete independent exec classification against the
two immutable F6 windows is complete:4183 terminated processes,38394 attempted
executions, twelve successful compiler/linker processes (six per explicit build)
and zero outside either window. Their exec and termination times both lie inside
the corresponding build window; no parser/termination issues were found.
Independent review `P0_BUILDER_TRACE_INDEPENDENT_REVIEW_04.md` SHA
70f561e3a953c59252085e508a37ecd8efd09b9510d1435d9befac133aa4c61a.
Handoff:
`_private_next/agents/qa_cpp_debug_tree/p0_test_c/INDEPENDENT_TEST_C_HANDOFF.md`
(SHA b01ae8b9ed88fd30c601e333bdaa43e09e7d27acb74717cbe38c675a7e873a4e).

The additional mandatory Circuit editor scope is tracked in
[DEV109_CIRCUIT_ACCEPTANCE.md](DEV109_CIRCUIT_ACCEPTANCE.md), with the dedicated
same-author role and independent verification boundaries. Its gates remain OPEN.

Normal Plugin Manager update of the same author's Circuit 1.9.6 candidate is
independently verified within installation scope: one native Update, packaged
binary admission, all 94 installed files exact, provider/category preserved and
all foreign registry entries unchanged. MAIN viewed the actual result and
Manager images. The loaded 1.9.5 implementation correctly remained active with
“Updated — restart required”; this wave does not prove fresh 1.9.6 activation.
Normal closure completed the full 500 ms observation, actual driver exit0 and
absence of all 960 traced processes. The complete 8,962 attempted executions and
99 executable paths contain zero compiler/linker invocations and no parser or
termination issues. Installer extraction/copy writes are distinct from binary
compilation. Three QA harness failures and five stderr lines are retained.
Independent report: `CIRCUIT196_NORMAL_GUI_INSTALL_INDEPENDENT_REVIEW_09.md`,
SHA256 `9f42731b861117b651ff42e865c70e218c9c5624e1ac87cf58e495380f2f556e`.
P0 E, remaining lifetime cases and full integrated acceptance remain OPEN.

The additive TeX form method uses new opcode30. Independent static review found
the installed Circuit1.9.6 SDK Event/State/Host storage, C entry point and all
operations1–29 unchanged. Installed admission, compatibility and runtime methods
remain unchanged; the new broker branch adds no compiler fallback. This static
result qualifies compatibility, rather than replacing actual current-source
installed tracing. The support catalog now records30 Host methods and46 admitted
headers and passes exact regeneration checking. LaTeX document Build runs the
configured native typesetter; it does not build the installed C++ Viewer.
