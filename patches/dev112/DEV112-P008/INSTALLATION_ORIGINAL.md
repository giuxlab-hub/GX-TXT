# GX-TXT DEV112-P008 installation and rollback

Framework version: 0.9.8.10-dev-112. Patch level: 008. Source: f691b0f6e1016cb9af3db30ba3d1c8b5ea91429c.
This is a cumulative patch. The primary route is the exact accepted P007
installation. Direct routes from pristine DEV112 Release 2, accepted post-P005,
and accepted P006 r5 are also admitted; sequential earlier patches are unnecessary.
Every route produces the same complete final framework byte/mode inventory.

Extract the complete delivery into a separate review directory. Use its matching
helper; do not extract the patch ZIP directly over a working installation.
Keep the ZIP and its matching helper together. Verify SHA256SUMS before use.
The helper in the delivery is `patch/apply.py`; the archive mirror also provides
`DEV112-P008-apply.py`. The helper performs a read-only check by default:

```sh
python3 -I -B patch/apply.py /absolute/framework patch/DEV112-P008.zip --check
```

Stop the intended framework and its writers before applying. Confirm the exact
target and retain an external receipt outside the framework:

```sh
python3 -I -B patch/apply.py /absolute/framework patch/DEV112-P008.zip --apply --stopped --owner-authorized --receipt /absolute/receipts/P008-apply.json
sha256sum /absolute/receipts/P008-apply.json
python3 -I -B patch/apply.py /absolute/framework patch/DEV112-P008.zip --check
```

Preserve that exact receipt and its separately retained SHA256. To restore the
accepted P007 preimage, stop all target writers and use the authenticated receipt:

```sh
python3 -I -B patch/apply.py /absolute/framework patch/DEV112-P008.zip --rollback --route post-p007 --stopped --owner-authorized --receipt /absolute/receipts/P008-apply.json --receipt-sha256 RETAINED_RECEIPT_SHA256
```

Other original routes are `r2`, `post-p005` and `post-p006-r5`; use only the
route actually identified by the retained application receipt. Original receipts
and rollback records remain untouched. The existing installer rejects changed,
unknown, mixed or incomplete managed sources, linked/hardlinked paths, tampered
archives/manifests and invalid rollback receipts. Unrelated user files, Sessions,
Datasets, user configuration and installed components are preserved.

The existing infrastructure provides atomic replacement per file, not an atomic
whole-tree transaction. Preserve any interrupted attempt and its receipt; a mixed
tree is refused until explicitly restored. No P008 activation on the owner's
working installation was performed. Installation/rollback qualification for all
four exact baselines is included in the independent delivery evidence.
