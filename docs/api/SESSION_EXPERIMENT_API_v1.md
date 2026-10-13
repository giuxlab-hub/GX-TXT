# Session Experiment API v1 — Duplicate Experiment (dev079)

All existing Tcl commands/signatures and the Phase 1 Session integration remain.
`sessionExperimentClone name ?root?` returns a fresh Session/Experiment identity,
Project relationship and actual Dataset=0, Workspace=0 and retained document counts.
It snapshots live notes without saving/switching the source; the GUI opens the clone
only after transaction and Project-index success. Source drafts are restored in the
same GUI process on return, using the normal Save/Discard/Cancel lifecycle.

Dev079 prioritizes reliable conservative duplication. Independent CORE preparation
(notes/objective/procedure, scripts, instruments, setup parameters, proven documents
and referenced managed resources/artifact layers) survives. Observations are empty;
all previous Dataset/Workspace/graph state, outputs, styles and bindings are excluded.
No Workspaces are reconstructed or partially preserved. Unknown optional state is
omitted with diagnostics. Unsupported modules start disabled at descriptor defaults,
with empty scientific/path inputs and no Run selection; reconfigure fresh inputs.

The optional [Experiment Duplication Policy API v1](EXPERIMENT_DUPLICATION_POLICY_API_v1.md)
lets future modules declare safe setup/configuration/documents and external references
without editing CORE IDs or implementing a clone engine. Existing modules remain
installable, discoverable and runnable with no declaration. Native compatibility
schemas and generation-bound classification use the existing document registry.
SHA-256 validates bytes, never scientific ownership; independent identical-content
preparation remains valid. No arbitrary author-text/Manifest path substitution occurs.

`sessionExperimentPreparationRead` and the existing read-only Script Bridge
`SESSION_EXPERIMENT_API_v1/preparation` return the Manifest receipt. It adds policy
ID/version and a `summary` of copied/reset/excluded/skipped objects with owner/reason.
Session > Duplication report opens `metadata/experiment_preparation.txt` after ordinary
completion, without an acknowledgement wizard. Mixed/unknown optional documents
are omitted and reported, superseding dev078's clarification cancellation policy.

Exclusive destination reservation, atomic commit, collision/cancellation and exact
Project-registry rollback remain. True integrity/filesystem errors abort and clean
owned staging; optional stale/deleted resource documents can be omitted safely.
Public Dataset/Workspace/Graph/Document/Script/Instrument authorities, Dataset page,
module algorithms and viewer functionality remain intact. Newly created scientific
state can be run/edited/saved/reopened normally in the independent destination.

Dev083 new duplicates record the current creator installation and a source Experiment
origin snapshot. The preparation-only scientific exclusions remain unchanged.
