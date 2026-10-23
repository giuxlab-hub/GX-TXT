# GX-TXT dev-111 r3 — maintenance patch DEV111-P001

**Compatible with original dev-111-r3 source; staged only, not installed.** No predecessor patch. Not for dev-110 or later framework revisions without independent review.

**Changes.** The Modules checkbox shows or hides an enabled module pane in Analysis without changing its separate Run selection. The selected-module label and two original actions (Script Module Builder and Reset selected module runtime) move beside search and wrap at supported widths. Existing Session configuration retains visibility.

**Exact baseline.** Public GitHub main 4daf135e49378eff1f413310bc17cf32f1928c44. Independent original author commit 83b391de4b81a87e4e76f477491371b58cdc3a40. These distinct commit IDs have matching eight relevant source SHA-256 identities. Original product.diff applied in an isolated maintenance checkout matches all six expected after hashes.

**Original binary packages.** DEV111-P001.zip is the unchanged author-supplied six-file patch; ROLLBACK.zip is the unchanged six-file original r3 preimage. Per-file hashes and original modes are in MANIFEST.json. Public MANIFEST.json and APPLY.md only redact machine-private paths. The unmodified original manifests and original private test evidence remain held privately.

**Permissions.** The original APPLY.md preflight pins file mode 0664 (decimal 436). A normal Git checkout mode 100644 typically becomes 0644, so the original installer will refuse a Git clone despite byte-identical code. Never bypass the mode refusal or alter an active installation just to satisfy source identity. The patch is designed for exact compatible installed/extracted r3 sources; a Git-clone-specific installer would require separate verification.

**Safe use.** Save and close GX-TXT before applying to an explicitly authorized compatible installation; use APPLY.md preflight and retain its backup/transaction journal. Rollback requires all six post-patch SHA-256 hashes and restores the exact original r3 files. The main branch, official archive, release markers, source Sessions and user datasets are untouched by publication.

**Evidence.** Focused Linux Tcl/native GUI tests reported in the original acceptance are summarized in VALIDATION_PUBLIC.md. Full scientific/GUI regressions and installed application test were NOT rerun during GitHub publication.

**Distribution.** Separate branch maintenance/dev111 and version-specific GitHub prerelease; original main dev-111-r3 and historical dev-108-only hotfixes remain unchanged. GNU GPL-3.0-or-later.
