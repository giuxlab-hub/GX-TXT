# Scientific field and complex sweep Dataset contract v1

This contract uses existing GX-TXT Canonical Dataset, Dataset Variable Schema v3, Dataset Metadata v1, Dataset Selection, Unit and Publication APIs. It defines scientific relationships for consumers of `NUMERIC_API_v1`, `RF_NETWORK_API_v1` and `MAGNETICS_API_v1`; it does not create a new storage or Dataset model.

## Complex frequency sweep

A sweep has one strictly increasing frequency coordinate variable with a stable variable ID and declared `Hz` unit. Each complex quantity has stable real and imaginary variable IDs with identical dimensions, sample count and physical unit. Magnitude and phase are derived values, not mandatory duplicate storage. Phase is radians unless the variable metadata explicitly declares degrees. Variable Schema v3 uses the frequency dimension ID and `coordinate_variable_ids` relation; group/component IDs identify related complex parts. Dataset Metadata carries namespaced fields such as `rf.reference_impedance_ohm`, `rf.port_count`, `rf.wave_definition`, and `rf.parameter_kind` when relevant. Imported source path, checksum and instrument/simulator identity remain normal provenance. Complex reference impedances require an explicit `wave_convention=power|traveling` choice before S-parameter conversion.

A consumer must verify that all selected variables belong to one Dataset, have the same frequency coordinate identity, matching length and compatible units before combining them. Numeric or RF operations receive raw arrays after this validation. Derived output is published through the normal Dataset Publication API with the source Dataset and variable IDs in provenance.

## Regular field

For a regular Cartesian field, each independent coordinate axis has a stable coordinate variable ID, physical unit and strictly increasing values. A scalar field variable declares rank 2 or 3, shape, dimension IDs and coordinate variable IDs in the same storage order. A vector field has three component variable IDs in one group with matching rank, shape and coordinates; the component basis is declared in metadata. The Dataset Metadata key `field.coordinate_system` declares `cartesian`, `cylindrical`, or `spherical`; keys `field.component_basis`, `field.quantity`, and `field.unit` state the physical meaning. Numeric interpolation and magnetic differential operators currently require Cartesian regular grids; coordinate transforms are explicit operations.

For unstructured fields, coordinate variables have point index dimension and an explicit 2D or 3D coordinate basis. Scalar/vector field variables share that point dimension. Mesh connectivity is represented by normal Dataset variables with stable identity or by a published scientific artifact reference; face orientation must be preserved for flux. A field consumer must verify point/field count, triangle index validity, component count, finite values, coordinate system, units and source provenance. Scattered interpolation may use points without connectivity; surface flux needs oriented triangles.

## Selection and storage

A Selection references stable Dataset and variable IDs and applies before raw mathematical processing. Storage Auto/HDF5 remains transparent through Canonical Dataset access and Table Stream where applicable. A calculation should not copy large field arrays into metadata or invent a separate Dataset registry. Dataset Metadata stores descriptive values and links, not bulk numeric payloads. Unknown metadata keys are preserved by the existing Metadata API.

## Failure behavior

Missing or incompatible coordinate IDs, nonmonotonic axes, mismatched complex parts, unit/coordinate conflicts and absent mesh connectivity must produce explicit diagnostics. A mathematical API does not silently rescale physical units or transform coordinate bases. NaN/Inf policy is explicit at the raw operation boundary.

## Touchstone v1 network import

`acq.touchstone` publishes an S-parameter `spectrum.table` with `frequency_Hz`, then `s11_real`, `s11_imag`, `s21_real`, `s21_imag`, etc. through the declared port count. The frequency axis is in Hz after applying the file unit. RI/MA/DB source encodings are converted into real and imaginary columns. The acquisition result records source provenance plus metadata fields `format=touchstone.sparameters`, `port_count`, `reference_impedance_ohm`, `source_representation` and `source_frequency_unit`. For S2P, file order is S11, S21, S12, S22; for higher port counts it follows Touchstone matrix order. The importer diagnoses unsupported Touchstone 2 keywords. Consumers still validate source identity and unit compatibility before RF conversion.
