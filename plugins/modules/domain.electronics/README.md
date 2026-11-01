# Electronics Library Domain Schemas

Independent Plugin Install API v1 package. Install with the existing Plugin Manager, or the supplied atomic Bundle v1 with declared companions. No network or scientific import runs on installation or catalog discovery.

Persistent Libraries remain independent of Sessions. Look up a source, review the selected records, then explicitly Import into Library. Later select individual entries/resources and use Import selected to Session; existing Acquisition handlers own RAW, SHA, publication and Dataset registration. Missing/disabled providers leave saved immutable packages intact and report unavailable capability. Credentials belong only to the existing protected Library Credential profiles, never Module Configuration.

## Offline reviewed suggestions (1.0.1)

The existing source-suggests-alternative relation explicitly declares `manual_suggestion: true`. The generic Browser accepts independently user-pasted TSV candidates, defaults Include off, and imports only checked rows as independent entries. Preserve exact manufacturer, MPN, supplier SKU/variant and original values. A supplier/user suggestion is attributed evidence, never a drop-in compatibility certificate. No network or credentials are required; the Mouser API read-through path remains separate.

Paste a header `candidate_id` followed by declared schema field names separated by tabs; each candidate key is stable within the chosen source attribution. `label` and `source_id` are optional columns. Parse, inspect, check individual candidates, choose source/user attribution and retain the literal suggestion/differences. Preview performs no writes; Cancel leaves Libraries/Sessions unchanged. Explicit Save commits selected entries and pinned directed edges in the existing single Library transaction. Exact duplicates reuse entries; changed existing candidate content requires its explicit pinned edit. No recursive suggestions or Session Datasets are created. Earlier schema-pinned entries remain compatible.

Use Copy schema TSV header for the actual installed field names. Parse and use
Return or Inspect selected candidate to review full manufacturer/MPN/SKU/variant
values and the literal original row. Search filters reviewed rows while retaining
checked identities; Uncheck all clears the whole selection. The final selected
review shows each target Entry/revision/SHA and full fields before Save. Original
paste changes are never silently discarded; stale previews require review again.
