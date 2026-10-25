# DEV111-P018 — Embedded native CAD Canvas Host

GX-TXT 0.9.8.10-dev-111 revision r3. Apply after the accepted cumulative P001-r2 through P017 updates, with GX-TXT closed. Restart the application afterward.

P018 adds a reusable CORE Native2D CAD Canvas Host, with Create/Attach lifecycle and selection, manipulation, cancel and navigation operations. Curve Workbench adopts the shared host while native C/C++ geometry, the existing CORE CAD controller, presentation and History services retain scientific ownership. The update also extends source-bound Dataset Transform responsive planning.

Installation (extract from a separate package directory):

    unzip -o DEV111-P018-PUBLIC.zip -d /path/to/gxtxt

Rollback: restore the exact previous source files from your prepatch backup and remove newly introduced P018 files. Do not apply directly to a later cumulative framework revision.

The original owner archive includes private scientific test evidence. The public archive preserves all functional Tcl/API source files, adjusts one previously approved public document link and normalizes two public module SHA256SUMS indexes. Exact source and checksum exceptions are recorded in MANIFEST.json. No new independent GUI tests are claimed by package publication.
