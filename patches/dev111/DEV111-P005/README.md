# DEV111-P005 — Corrected Native Preview activation

For GX-TXT 0.9.8.10-dev-111 r3 on compatible Linux x86_64 after P001, P002, P003 and P004.

Adds the existing native Preview provider to the normal CMake build, supplies its matching native Linux component and wires the existing Tcl Preview worker to load the provider explicitly. Scientific source ownership, provider admission, module enablement and existing CORE fallbacks remain authoritative.

With GX-TXT closed and the prerequisite files matching MANIFEST.json, extract:

    unzip -o DEV111-P005-PUBLIC.zip -d /path/to/gxtxt

This corrects the original P005 package; do not install its superseded first ZIP. If an earlier P005 example package was installed, its added example files require independent removal as described in the original private author instructions. Save a framework backup before extraction. For rollback restore the exact prior source/binary files from that backup.

The three executable/source payload files in this public ZIP are byte-identical to the corrected owner deposit. This distribution intentionally excludes internal evidence.
