# Scientific Spectrum CSV and JCAMP

Independent normal Plugin Install package. Actual source CSV/JCAMP bytes are retained; no numeric data is invented from annotations, pictures or external references. Uses existing CORE Scientific Spectrum Import/Spectrum APIs for parsing, finite/monotonic axis/units and sample admission; no duplicate scientific parser. A persistent Library entry is independent of Sessions. Only an explicit later selected import invokes the standard Acquisition transaction, retaining RAW/SHA/Variable Schema/Library provenance.

CSV semantics are mandatory explicit inputs: spectrum_kind, x_quantity/x_unit,
y_quantity/y_representation/y_unit, selected columns/header/delimiter. No axis or
physical meaning is guessed from a filename. Direct standard Acquisition uses
its ordinary Configuration fields; missing scientific semantics fails inspection.
JCAMP uses actual supported source headers. Library dispatch additionally stages
a bounded data-only context for a validated Entry's parser_options, pinned to the
original resource SHA and separately pinned context SHA before inspect/import.
A sibling filename alone does not confer host authority or execute anything.
Malformed/mismatched/orphan context is refused. Exact options and scientific
source hash/units/representation are retained in normal Dataset metadata.
