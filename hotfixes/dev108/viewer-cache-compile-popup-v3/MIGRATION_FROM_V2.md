# GX-TXT dev-108 Viewer hotfix v3: migration from v2

Hotfix.2 supersedes hotfix.1. They are NOT stackable.

To update an installation already patched with v2: first close GX-TXT, use the original v2 installer and its preserved verified backup to roll back fully. Without that backup, restore a pristine official dev-108 installation. Do not overwrite arbitrary source edits. The new v3 preflight requires both exact original public Git dev-108 blobs and rejects v2, any unknown modifications and all other framework versions.

Then follow README.md: --check, --apply, and keep the exact rollback command printed. The patch modifies Python and Tcl GUI source.

v3 replaces /dev/tty/fallback logging with a per-event nonmodal Tk build notice and persistent compiled/reused completion status. Project-local caching is retained; new temporary projects can compile on first use. Script Job stdout/stderr remain untouched.

Dev-109 and all other versions are incompatible BY POLICY. Main dev-108 remains unchanged.

Six isolated tests passed. Complete Debian GUI/Clang integration is NOT VERIFIED by publication.