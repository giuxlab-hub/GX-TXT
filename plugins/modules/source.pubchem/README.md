# source.pubchem Remote Library Importer

Independent Plugin Install API v1 package. Install with the existing Plugin Manager, or the supplied atomic Bundle v1 with declared companions. No network or scientific import runs on installation or catalog discovery.

Persistent Libraries remain independent of Sessions. Look up a source, review the selected records, then explicitly Import into Library. Later select individual entries/resources and use Import selected to Session; existing Acquisition handlers own RAW, SHA, publication and Dataset registration. Missing/disabled providers leave saved immutable packages intact and report unavailable capability. Credentials belong only to the existing protected Library Credential profiles, never Module Configuration.

Official PUG REST and PUG View: https://pubchem.ncbi.nlm.nih.gov/docs/pug-rest,
https://pubchem.ncbi.nlm.nih.gov/docs/pug-view. Names, exact CIDs and qualified
smiles:/inchi:/inchikey: queries use documented PUG REST identities/properties.
Ambiguous results require selecting an exact CID. PUG REST SDF3D falls back to
actual2D only on404. Existing molecule_io validates source geometry; computed3D
and conformer identity remain explicit. PUG View GHS information stays contributor
attributed, including unknown jurisdiction/conflicting claims; it is not an SDS
compliance assertion. Spectral information is stored as actual external/source
annotation when no numeric trace is supplied. PubMed IDs produce bibliography-only
entries, not invented titles/articles/PDFs. This bounded first retrieval includes
at most50 PubMed cross-references; further references remain upstream.

Live author read-only acetone test on2026-10-28: CID180, actual structure,
source-specific GHS/spectral annotations and PubMed references retrieved. This
is separate from persistent Library/Session/native GUI acceptance. Public capture
and exact SHA are in the task's live01 evidence; no API key is required.

Version1.0.1 declares the exact emitted record types for declarative Library view scopes: `chemistry.compound`, `chemistry.structure`, `chemistry.safety_claim`, `chemistry.spectrum_reference`, `scientific.publication`. Provider IDs refer to their installed domain schemas. These metadata changes do not alter normalization, credentials, HTTP or storage policy. Source discovery never makes a network request.
