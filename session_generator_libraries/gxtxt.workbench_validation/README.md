# Workbench Source Practice 1.0.0

Installable Session Generator Library v1 candidate:
`org.giuxlab.gxtxt.workbench_validation`.

Generators `cad_geometry_practice` and `planar_em_practice` create source-only
ordinary Sessions through the existing host transaction. See each generated
`STUDENT_GUIDE.md` for the existing GUI controls and explicit scientific limits.
No original Session, external dataset, CAD engine, solver, Analysis module or
runtime dependency is used during generation. Python's standard library is
sufficient. Each generator carries the existing source utility, preserving the
normal individual-generator export/copy layout as well as whole-library use.

Each `session_recipe.py` is an **unmodified** copy of the existing sanctioned source
recipe at
`session_generator_libraries/gxtxt.numerical_examples/generators/calibrated_digitizer/session_recipe.py`,
committed GX-TXT source `2d9441aa298135f8897de0d94466d156f7e4f0b8`, SHA256
`4c6124ca1df8e7d4ac47d118a9dc5e13fa326ae89caa28588dec1d5de040908c`.
It supplies the existing `configure(root, generator_id, datasets, modules,
experiment, extra_manifest=None)` format, table/binary source copies and
Dataset/Manifest storage. There is no replacement registration or storage code.
Each generator is self-contained after installation and its Session remains
self-contained after generation; neither imports another installed library.
Original utility authorship/license is
retained; the framework and these original fixtures use GPL-3.0-or-later.

MAIN1 alone integrates, registers, accepts, packages for release and synchronizes
the Debian server's `session_generators/archives` and `expanded` sections. This
source candidate is not an installed or accepted release. Author diagnostics
create disposable output directories and test source structure/determinism and
the existing Library v1 validator. Subsequent functional/scientific acceptance
requires ordinary GUI **Generate Session** provenance and independent QA.
