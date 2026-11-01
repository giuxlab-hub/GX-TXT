# Dataset Group Producer API v1

P030 adds a capability-bound public facade to the existing Dataset Group v1,
Publication v2, Dataset Authority, Namespace and Catalog owners. It reuses their
storage and transaction. Admission depends on a registered producer identity
and actual operation capability, with no producer-kind hardcoding.

Grouping is optional. Existing publications and Acquisition results retain their
behavior. Existing Group descriptors/packages remain readable. Producer-created
Groups add inert `producer_module` and `producer_api` fields; every Group uses
the same lifecycle independently of whether its producer is Acquisition,
Viewer, Analysis, processing, Python, Octave or another approved producer.

| Public Tcl operation | Behavior |
| --- | --- |
| `datasetGroupProducerReviewV1 capability session datasetIds` | Review schema `gxtxt.dataset_group_review.v1`, current `session_token`, actual `producer_module`, and `dataset_revisions`. Empty IDs obtain the Session token for publication. |
| `datasetGroupProducerCreateV1 capability session definition review` | Create a Group of exactly the reviewed owned canonical outputs without payload copying, replacement or republishing. |
| `datasetProducerPublishBatchV1 capability session request` | Existing create-only Publication v2 batch result, with `dataset_group` only when requested; one Authority transaction commits or aborts everything. |

CORE supplies the existing opaque module capability in activation/viewer context.
Retain it for callbacks; do not manufacture capabilities or accept an actor ID
from untrusted requests. Restricted clients get bound facades, never the issuer.
Catalog advertising alone grants no Script Bridge/native capability. Review
revisions are opaque complete UTF-8 strings: retain and return each unchanged,
without parsing, splitting, normalizing, hashing or truncation.

All operations require the current open Session. Commit rechecks its lifetime,
registered producer, actual Dataset owner, authorized Namespace, full persisted
Dataset revision, actual canonical payload SHA, contract and provenance. Moving
a foreign output into the producer namespace does not transfer ownership. An
existing explicit shared-namespace grant permits grouping the producer's own
outputs there. Administrative mutation authority is not granted.

A batch request has only `session_token`, `outputs` (1–64 ordinary Publication
v2 publish_series requests) and optional `dataset_group`. It is create-only;
existing owned replacement APIs are unchanged. The optional Group must contain
exactly all new output IDs. A caller cannot select a different publication
identity. Failure in publication or Group validation aborts the same journal,
even when a trusted outer transaction catches the inner error. Omit
`dataset_group` for independent outputs and no implicit grouping.

A Group definition has `group_id`, `display_name`, qualified `group_contract`,
`primary_dataset_id`, ordered `members` and optional asserted `namespace`.
Each member has `dataset_id`, qualified `role`, boolean `required`, and optional
asserted `contract`/`canonical_sha256`. CORE pins authoritative contracts,
fingerprints and source provenance and refuses mismatched assertions. IDs must
be exact, valid and unique; primary must be a member; all members must share one
authorized Namespace. Existing membership collisions are refused. This facade
bounds a reviewed Group to 1–64 members. Existing storage keeps its prior
1000-member compatibility bound and 1 MiB total descriptor bound.

`datasetGroupHostReviewV1 session datasetIds` and
`datasetGroupHostCreateV1 session definition review` are separate host/admin
operations, unavailable from module-private contexts. The persistent primary
Dataset menu exposes **Create Dataset Group…**. It lists ungrouped canonical
Datasets, contracts, namespaces and actual producers; the user selects roles,
required flags and primary member and confirms the exact selection. Full
revisions and Session lifetime are pinned before confirmation and rechecked
at commit. This explicit host authority may group independently produced
Datasets in one existing Namespace, without moving or rewriting them.

Move, rename, detach, ungroup, integrity diagnostics, Browser hierarchy, full
Group ZIP export/import and cold reopening continue through existing owners.
There is no arbitrary Tcl execution, Registry write, filesystem grant or silent
permission to group protected foreign outputs.

SOURCE_NOTE_API_v1 remains a distinct association between a canonical Markdown
note and its exact Python/Octave/C++ source file, inspectable through its public
API. A source file is not automatically a Dataset: do not create a second
Dataset merely to establish a Group or replace source associations with Groups.

Curve Digitizer2.0.20 remains owner supplied unchanged. Combined mode publishes
one Dataset and inherently needs no Group. Separate mode can later use this
generic public interface for an optional Group of its real outputs while
preserving IDs, calibration/curve schema and provenance. P030 does not alter its
caller, package or binary or run additional functional tests on it. Qualification:
`OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST`. Independently authored
test-only producers qualify the generic interface. Actual Script Bridge/native
bindings and admission are documented with their respective supported APIs.
