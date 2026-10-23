# DEV111-P002 — apply and rollback

**Verified and approved by the GX-TXT project owner.** Requires dev111 revision r3 plus DEV111-P001 already applied.

Close GX-TXT. Verify the published distribution ZIP SHA-256 and extract it outside the framework. In the extracted patch directory run:

    bash apply.sh /path/to/gxtxt

The original installer verifies the six post-P001 files, native dependency, all old file hashes and absence of the three new files, then writes transaction backups and updates 18 targets.

For rollback, close GX-TXT and run from the same extracted directory:

    bash apply.sh --rollback /path/to/gxtxt

Rollback restores the exact post-P001 state and removes the three P002 additions. Do not roll back P001 before P002. Do not override a hash/platform refusal or replace active files manually. Compatible Linux x86_64 / Tcl 8.6 is required.

The installer and manifest are preserved verbatim from the original verified patch. The archival r3 source and framework main branch are not rewritten.
