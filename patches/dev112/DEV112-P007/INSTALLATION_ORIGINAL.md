# DEV112-P007 installation and rollback

This cumulative patch supports pristine DEV112 Release 2, the exact accepted post-P005 baseline and the exact delivered P006r5 installation. The helper verifies complete managed bytes and modes. Modified, partial or other baselines refuse before writes. Framework version remains 0.9.8.10-dev-112; patch level becomes 007.

Extract the delivery outside the framework. Stop GX-TXT and retain a backup. Operator flags acknowledge that the target is stopped and installation authorized; the helper does not stop processes or grant permission. Run from the extracted delivery directory:

```bash
framework='/absolute/path/to/framework'
sha256sum -c SHA256SUMS
python3 patch/apply.py "$framework" patch/DEV112-P007.zip --check
receipt_dir="$(mktemp -d "$PWD/receipts-P007.XXXXXX")"
python3 patch/apply.py "$framework" patch/DEV112-P007.zip \
  --apply --stopped --owner-authorized \
  --receipt "$receipt_dir/apply.json" > "$receipt_dir/apply-audit.json"
sha256sum "$receipt_dir/apply.json" > "$receipt_dir/apply.json.sha256"
python3 patch/apply.py "$framework" patch/DEV112-P007.zip --check
```

Proceed only after each command succeeds. Retain the authentic completed receipt, independently retained receipt SHA, successful audit, archive and helper together outside the framework. The apply audit names the recognized origin route. No rollback of P006r5 or installation of previous patches is required to upgrade directly.

For rollback, stop GX-TXT and use the same framework instance. Set route to the origin recorded in the successful apply audit: `r2`, `post-p005` or `post-p006-r5`. Set receipt_sha from the independently retained value:

```bash
receipt_dir='/absolute/path/to/the/original/receipt-directory'
receipt_sha='RETAINED_SHA256_OF_COMPLETED_APPLY_RECEIPT'
route='post-p006-r5'
python3 patch/apply.py "$framework" patch/DEV112-P007.zip \
  --rollback --route "$route" --stopped --owner-authorized \
  --receipt "$receipt_dir/apply.json" --receipt-sha256 "$receipt_sha" \
  > "$receipt_dir/rollback-audit.json"
```

The helper requires the authentic receipt bound to this archive, manifest, origin, absolute framework root and installation instance. It refuses an altered managed postimage or mismatched receipt. Rollback restores that installation's exact original managed bytes/modes and removes patch-added managed files. Unrelated files, configuration and Sessions are preserved. Plugin Manager has its existing separate lifecycle.

Atomicity is per file. If interrupted, preserve the partial state and receipt and restore from backup; do not assume automatic continuation or a whole-tree transaction. The helper deliberately refuses mixed inventories. No production installation was activated during development or validation.

## Preinstalled Curve Digitalizer companion

P007 updates the existing preexpanded `preview.curve_digitizer` module and its SHA inventory as managed framework files on every admitted route. It requires no separate Plugin Manager installation. The version-pinned DEV111-P032 carrier and original distribution provenance remain historical records; the P007 `FILES.json` defines the current framework-managed module contents. The current P007 framework ZIP and its expanded distribution mirror are verified against the same complete inventory.
