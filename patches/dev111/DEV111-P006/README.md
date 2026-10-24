# DEV111-P006 — Optional Preview GUI API and shared icons

Target: GX-TXT 0.9.8.10-dev-111 revision r3, on the cumulative P001-r2 -> P002 -> P003 -> P004 -> corrected P005 installation.

Adds optional Preview GUI v1, guiMount/guiDispose, shared UI Field widgets/icons, viewport chrome controls, and an additive Plot v4 display adapter. Existing Dataset owners, native workers, Module admission, C++ ABI and scientific results remain unchanged.

Close GX-TXT, save an exact backup of the framework files, confirm the prerequisite source hashes (see MANIFEST.json and public_exceptions), then apply:

    unzip -o DEV111-P006-PUBLIC.zip -d /path/to/gxtxt

For rollback restore the previous files from your backup, and remove the two new P006 API files. A standalone rollback installer is not included.

The full author deposit is retained privately. The public archive contains the same eleven functional source/API changes byte-identical, three public API documents with previous private-link cleanup preserved and two reconciled Plot Dataset SHA256SUMS inventories; those five public changes are explicitly recorded in MANIFEST.json.

Patch-specific GUI validation source scripts were not deposited with P006. The separate validation branch contains read-only verification and manual native follow-up.

