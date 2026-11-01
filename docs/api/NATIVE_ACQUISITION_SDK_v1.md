# Native Acquisition SDK v1

This is the additive `acquisition_v1` Development target under the existing
`ACQUISITION_HANDLER_PLUGIN_API_v1`. It creates a genuine Acquisition package;
there is no Viewer design or authored Tcl adapter. Existing Viewer SDK/ABI26/41,
policies, compiled Markdown/UML packages and legacy Acquisition handlers retain
their previous admission.

The actual project interface is documented in
`validation/dev111_p032_toolchain/PROJECT_TRANSPORT_BATCH_A_01.md`. Registered
`.cpp`/`.hpp` and typed Tcl/Python helper files share its full source revision and
CAS. Profiles bind defined, compiler-checked free callbacks with exactly:

```cpp
gx::AcquisitionResult inspect(gx::AcquisitionHost& host,
                              const gx::AcquisitionRequest& request);
```

The same signature applies to recognize and import. Test invokes the actual
import callback and discards its outputs. Each profile is qualified MODULE/PROFILE.
No callback string is evaluated. A generated finite factory calls only the
admitted definitions. Zero profiles is a valid unfinished project; Validate,
Build and Export require at least one real profile. The existing fixed Clang
driver, lexer/header review, resolved AST, managed requests and deterministic
standard package writer are reused. Compiler flags and extra libraries are not
authored fields.

`AcquisitionValue` represents bounded inert metadata: null, UTF-8 text, boolean,
signed 64-bit integer, finite real, object or array. Its constructor helpers are
`acquisition_text/integer/number/flag/object/array`. It is not a path, command,
Dataset writer or capability. Metadata is bounded to 196608 bytes, depth24 and
32768 nodes; wire frames are bounded to 262144 bytes. Numeric samples do not use
this metadata transport and retain their declared missing-value/NaN semantics.

`AcquisitionRequest` supplies phase, qualified_profile, sources, config, mapping
and limits. Source descriptors contain source_index, logical_name, size,
source_sha256 and full_sha_reviewed. An unavailable inspection SHA is an empty
SDK string; Test/Import require actual reviewed SHA. Actual selected paths and
FDs stay in a separate CORE broker. The native actor receives neither.

| SDK method | Existing host operation and result |
| --- | --- |
| source_info(index) | source_info: immutable current SourceDescriptor |
| source_read(index,offset,count) | source_read: SourceChunk with exact raw bytes, offset, total_size, EOF; count1..65536 |
| progress(phase,message[,current,total]) | progress: CORE-owned bounded progress acknowledgement |
| cancelled() | cancelled: current live request state |
| prepare_output(definition,row_count,variables) | prepare_output: PreparedOutput with opaque output_id and variable byte counts |
| output_write(output,variable_id,offset,bytes,count) | output_write: sequential typed local chunk1..65536 bytes, acknowledged after authorization and local write |
| output_finish(output) | output_finish: provisional PreparedReference output_id |
| helper_call(declared_helper_id,args) | helper_call: separately admitted managed helper result; unavailable service explicitly refuses |

Each module requests exact operations in its capabilities; each profile requests
a subset. Actual CORE admission intersects those with current phase/service
availability and rechecks live package/profile/source/Session/cancellation state.
Declaring a profile or API catalog row grants nothing. Inspection cannot prepare
outputs. Helpers being registered, packaged or named by C++ does not establish
their execution support. SDK host calls are serialized by the trusted worker;
ordinary same-process threads may perform local work.

Prepare uses exactly `{definition,row_count,variables:[{variable_id,schema}]}`.
The definition is preflighted by existing Publication/contract/namespace owners;
the caller cannot set producer/actor/protected provenance. Rank1,64 Datasets,
128 variables and existing512MiB-variable limits apply. The SDK exposes no buffer
paths. CORE creates all empty ordinary typed files, supplies private identities to
the trusted worker, and authorizes each offset/count/chunkSHA before local write.
Numeric bytes never cross the Tcl/base64 control lane. Producers supply the
declared numeric dtype's little-endian bytes; this adapter does not reinterpret
samples or convert NaN to JSON.

Finish closes local write handles and sends exact variable_id/byte_count/SHA
receipts. Import result uses `{prepared_outputs:[{output_id}],warnings?...}` and
may explicitly request the existing optional Group definition. References remain
provisional until the actor exits normally, no process descendants can remain,
and CORE verifies full byte counts/hashes, source SHA and live authority. Existing
prepared-numeric/Publication v2/RAW/optional Group transactions alone commit.
Test validates then discards. No canonical success is returned by C++ itself.

Before loading the authored library or running static initializers, the fixed
worker closes unrelated FDs and installs default-deny Landlock filesystem rules.
Only exact reviewed binary/system runtime files are readable. The exact private
CORE buffer root admits WRITE_FILE/TRUNCATE only, without read/list/create/
remove/rename/exec rights. Missing supported enforcement fails closed.
New-target seccomp denies fork/vfork/process clone and exec (EPERM), clone3
(ENOSYS), foreign/x32 syscall ABI; clone is allowed only with CLONE_THREAD.
This prevents a descendant retaining buffer FDs after worker exit. Existing
Viewer fork/thread behavior is unchanged. These are filesystem/process lifetime
restrictions, not a general account or network isolation claim.

Build/Export use the existing Development CLI names. Export includes exact
source/helper roster, finite factory, separate SDK/adapter/policy, validation and
build/header receipts, binary and normal checksums. `runtime_inspect` validates
the distributed closure without compiling or CDLL-probing it and returns
`gxtxt.acquisition_runtime_admission.v1`. CORE normal module registration,
PackageVerify, enablement and live profile admission remain required around that
inert receipt. Native run/Test/Import use CORE's actual managed broker; old Viewer
run/prepare/test paths explicitly refuse this target. C++ and Python helper notes
use the existing SourceAuthoring owner, typed source CAS and portable lineage;
Tcl helper notes are explicitly unavailable. Canonical note GUI attachment and
independent helper acceptance are separate qualification gates; this API
description does not claim them passed.

Producer settings use optional ordered `config_fields` in the same source project
(older projects default to []). The supported inert scalar declarations and exact
CAS/descriptor/source ZIP boundaries are documented in
`validation/dev111_p032_toolchain/CONFIGURATION_FIELDS_C3_01.md`. They export normal
Module `[config]`/`[config.ID]` fields/defaults. Existing ModuleCfg alone stores
runtime values; CORE must normalize by declared types and capture immutable
schema/config identity. No settings field grants source paths or an operation.
The read-only `typed_config_payload` helper validates already normalized values;
it is not a string parser/default store or live module authority.

Optional `input_contracts` and `provided_contracts` source declarations emit the
existing normal Contract Registry descriptor sections. Exact IDs/description/
parents/source hashes survive source import; malformed/local cyclic declarations
refuse. Unknown external parents remain declarations, not compatibility proof.
Actual CORE provider/override/dependency/combined-graph and scientific admission
still applies. See `validation/dev111_p032_toolchain/CONTRACT_DECLARATIONS_C4_01.md`.

The fixed subordinate Python/Tcl helper actor and its inert wire contract are
documented in `validation/dev111_p032_toolchain/HELPER_WORKER_D1_01.md`. It receives
one metadata value and returns one bounded metadata value, with no RAW or output
buffer authority. Tcl uses the existing native JSON typed-node codec in a bounded
safe interpreter in the same worker PID. Python uses the existing Acquisition
filesystem/process guard before authored execution; no Python language, account
or network sandbox is claimed. The actual CORE dispatcher is wired under the
existing Acquisition Job/Resource lifetime, with module/profile intersection,
exact roster/source SHA, PID/factory/guard checks, forced live owner checks before
invoke/during/final, capped diagnostics and reap before return. Its presence is
reported by `native_helper_runtime_available`; no flag grants `helper_call`.
Per-request limits are 32 calls, 1 MiB cumulative metadata/diagnostics and 30 seconds;
the parent deadline is 6 seconds per call. Actual normal-package C++→Python/Tcl
author evidence and uncovered independent gates are recorded in
`validation/dev111_p032_toolchain/HELPER_BROKER_D2_01.md`.
