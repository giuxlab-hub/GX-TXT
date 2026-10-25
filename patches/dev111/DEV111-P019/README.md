# GX-TXT DEV111-P019 — Shared advanced CAD tools

Cumulative update for GX-TXT 0.9.8.10-dev-111 revision r3. Apply after the complete DEV111-P018 patch on a compatible installation, with the application closed.

Adds shared advanced CORE CAD tools for construction, topology, defining-control edits, relationships, dimensions and direction markers. Curve Workbench uses the public controller while the Native2D solver, C++ presentation, scientific Dataset owners and CORE History keep their authoritative responsibilities. The update stabilizes constrained-drag target synchronization and draft Undo admission.

Installation:

    unzip -o DEV111-P019-PUBLIC.zip -d /path/to/gxtxt

Restart the application. To roll back, restore the exact P018 file versions saved before installing and remove newly introduced P019 files.

The original owner deposit remains privately preserved. This public archive contains the unchanged 26 functional/API Tcl files plus two Workbench module checksum indices updated to reference only redistributed public files. Internal acceptance evidence and original test fixtures are held separately. See patch_notes/DEV111-P019/MANIFEST.json for byte-level identity and prerequisites.
