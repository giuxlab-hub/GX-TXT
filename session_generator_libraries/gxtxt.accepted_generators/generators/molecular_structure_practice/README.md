# Molecular Structure Practice 1.0.0

A source-only template Session Generator using the existing Session Generator API v1. It copies two licensed molecular SDF inputs, an exact reference manifest and a normal-workflow guide into a fresh Session. CORE creates the Session Manifest and generation provenance. It embeds no Dataset registry, completed analysis, native geometry or renderer result, and executes no generator program.

Use the normal registered Generate Session workflow. Import each source through the existing Molecule Viewer and `acq.molecule_structure` provider. The resulting canonical contract is `molecular.structure`; Dataset IDs are determined by that importer. See `template/STUDENT_GUIDE.md`. Scientific acceptance remains separate from source-only generation.

Bundled SDF bytes and their CC0-1.0 attribution are preserved from `viewer.molecule_3d`'s existing library; see `THIRD_PARTY_NOTICES.md` and the generated reference manifest.
