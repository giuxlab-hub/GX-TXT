# Contract Visualizer API v1

Configuration → Runtime → Contracts projects the installed semantic Registry,
including literal legacy media IDs, definition owners and versions, inheritance,
recommendations and effective selection. Open and embedded Preview have separate
persistent preferences. Configuration → Modules → Contract Visualizers filters
actual declared roles through the ordinary Module browser and Plugin Manager.
Missing owners, disabled or removed providers retain the preference and show a
diagnostic. Dataset-aware resolution pins the exact Session, payload reference
and complete Dataset revision before dispatch; a stale choice refuses.

CORE resolves installed providers over the existing Contract Registry, Viewer
Provider, Dataset Preview and Configuration APIs. Open and embedded Preview are
separate capabilities and separate preferences. No contract or Dataset store,
package installer, renderer or importer activation policy is replaced.

An ordinary installed module may opt in:

```ini
[contract_visualizers]
api_version=1
ids=markdown_document

[contract_visualizer.markdown_document]
name=Markdown Documents
contracts=document.text
targets=open
viewer_id=markdown_documents
inheritance=exact
document_kinds=markdown
```

The qualified provider ID is `module_id/provider_id`. Open requires a real
declared/enabled Viewer ID in that same module. Preview requires an ordinary
genuinely admitted Preview module and uses its existing descriptor/matching/
availability owner. `targets=preview` does not imply Open support. Inheritance
is `exact` by default; `declared` explicitly admits the existing transitive
`contractSatisfies` policy. Optional `media_types` and `formats` lists further
restrict actual canonical Dataset admission. All lists are bounded and unique.

A legitimate installed contract owner may declare in `[contract.CONTRACT_ID]`:
`recommended_open_visualizer=MODULE/PROVIDER`, independently
`recommended_preview_visualizer=MODULE/PROVIDER`, optional `version` and
`schema_identity`. Recommendations do not install, enable or force a provider.
Conflicting explicit schema identities refuse specialized resolution. Mere
consumer/output references do not replace a removed semantic provider.

Public Tcl operations in `::GX`:

- `contractRegistryDescribe contract`: actual owners, status, parents, consumer/
  producer references and qualified recommendations. Installed-disabled owners
  retain their declaration; uninstall removes it through normal Module catalog
  refresh. Existing Dataset bytes/metadata remain untouched.
- `contractVisualizerProviders`: declarative installed role records, validity,
  actual available targets and unavailable reasons from existing public owners.
- `contractVisualizerCandidates contract open|preview ?dataset_id?`: admitted
  compatible providers. Dataset-aware matching checks current canonical identity
  and actual document/Preview predicates.
- `contractVisualizerResolve contract open|preview ?dataset_id?`: data-only
  resolution with preference, selected token, selection source and diagnostics.
- `contractVisualizerPreferenceGet contract target`: retained token or `auto`.
- `contractVisualizerPreferenceSet contract target token|auto`: existing
  Configuration CAS/commit. A new choice must be installed, available and
  compatible. Missing saved preferences remain retained and diagnosed.
- `contractVisualizerOpen dataset_id ?resolution?`: validate/recheck the
  selected full Viewer and exact canonical reference, then use `viewerOpen`.
  It never executes a command from Dataset metadata or starts associated code.

Order: explicit valid user preference, unique available owner recommendation,
unique compatible provider, otherwise safe CORE fallback with reasons. Competing
providers never silently win by name/order. Missing/conflicting contract
definitions prevent specialized dispatch. Open/Preview preferences persist in
existing protected Configuration fields `contracts.open_visualizers` and
`contracts.preview_visualizers`; role declarations never mutate installed files.

Script Bridge exposes `providers`, `candidates`, `resolve`, `preference_get` and
`preference_set`; Contract Registry v1 additionally exposes `describe`. Host-only
Open is not a script execution capability. Native Builder/SDK authoring and GUI
integration are qualified separately; declaration presence is not acceptance.

Normal installed Acquisition modules remain always available while present.
A non-CORE managed Acquisition package may be removed through the existing
Plugin Manager even when its descriptor is nonselectable. CORE protection,
managed ownership/type/path checks, active-resource quiescence and loaded-code
restart guards still apply. No ordinary Acquisition enable/disable control or
new activation policy is introduced. Removing the unique contract owner leaves
canonical scientific files and saved visualizer preferences intact; compatible
reinstallation restores semantic discovery without rewriting those files.

The Runtime Contracts view keeps its live readonly registry projection separate
from uncommitted dropdown choices. Native popup visibility alone does not
recreate controls. Real registry, provider activation, Session or persisted
preference changes refresh the view; explicit Refresh remains available. Apply
and Restore Auto use the existing Configuration compare-and-swap owner.

## Literal canonical provenance constraints (additive P035)

An installed provider and Builder `contract_visualizer` role may optionally
declare `match_provenance_fields`, a dictionary of at most32 distinct top-level
provenance fields and exact nonempty literal values (4096bytes total;512bytes
per value). Candidate selection with a canonical Dataset requires all those
values in its protected registered provenance. Missing, malformed or conflicting
values refuse that provider. Unconstrained declarations retain existing behavior,
including legacy non-dictionary provenance. No filesystem, name suffix, Variable
label, subtype guess or producing module kind supplies implicit authority.

For example a spectroscopy application can declare
`match_provenance_fields={spectrum_kind IR x_quantity wavenumber}` for
`spectrum.scientific`, target Open. CORE contains no IR-specific routing value.
Unknown/RF/FFT/NMR kinds cannot acquire that automatic route merely because they
share the generic spectrum contract. Existing preferences remain stored; an
incompatible preference produces a diagnostic and the safe CORE fallback.

Datasetless provider catalogs remain useful for choosing preferences; actual
Open always revalidates the Dataset-aware result and its exact revision. Legacy
Preview Open of a canonical spectrum now uses this same admitted resolution in
Auto mode. Loose files with no canonical scientific identity retain ordinary
CORE/system handling rather than receiving an inferred scientific domain.


P035 constrained scientific facts also recognize actual producer-provided
structured metadata. `match_provenance_fields` remains a bounded literal-key
constraint: each required value must exist in canonical Dataset provenance or
the existing public structured metadata, and every present value must agree.
Missing fields, contradictory facts or unreadable metadata refuse the candidate.
This supports legitimate Acquisition producers whose scientific annotations are
metadata while their provenance is narrative, without guessing from names,
filename, producer kind or Viewer identity. Old unconstrained providers require
no metadata read and retain their existing semantics. These are presentation
eligibility facts, never new scientific, filesystem, Script or native authority.
