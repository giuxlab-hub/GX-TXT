# DEV112-P006 installation

The cumulative patch accepts GX-TXT DEV112.r2 or the exact post-P005 state. P001–P005 do not need to be applied separately. The framework version remains 0.9.8.10-dev-112 and the patch level becomes 006.

Extract this delivery outside the framework. Stop GX-TXT and retain a backup before making changes. The --stopped and --owner-authorized flags are operator acknowledgments: the helper neither stops processes nor establishes authorization.

Run the following Bash commands from the extracted delivery directory, replacing the framework path:

    framework='/absolute/path/to/framework'
    sha256sum -c SHA256SUMS
    python3 patch/apply.py "$framework" patch/DEV112-P006.zip --check

Continue only if the check recognizes an accepted baseline. A modified framework or a different version must first be restored to the correct baseline. Do not force recognition.

Create a new receipt directory outside the framework and apply the patch:

    receipt_dir="$(mktemp -d "$PWD/receipts-P006.XXXXXX")"
    python3 patch/apply.py "$framework" patch/DEV112-P006.zip \
      --apply --stopped --owner-authorized \
      --receipt "$receipt_dir/apply.json" > "$receipt_dir/apply-audit.json"

Confirm exit code zero and result PASS in the audit. Retain the receipt, audit, original archive and helper together. Save the completed receipt's SHA separately:

    sha256sum "$receipt_dir/apply.json" > "$receipt_dir/apply.json.sha256"
    python3 patch/apply.py "$framework" patch/DEV112-P006.zip --check

The framework check does not execute the complete functional campaign. Use the normal Plugin Manager with the current packages in packages/: ORION 1.0.11 and Scientific Image Inspector 0.4.37. Older carriers in distribution/packages history do not identify the current versions. These two packages are delivered as is at the owner's request.

## Framework rollback

Stop GX-TXT again. Set receipt_dir to the directory used for the original installation and receipt_sha to the SHA retained after successful application. Verify the receipt against that independently retained value:

    receipt_dir='/absolute/path/to/receipts-P006'
    receipt_sha='RETAINED_SHA256_OF_THE_COMPLETED_RECEIPT'
    route='post-p005' # Use r2 if the original baseline was DEV112.r2.
    python3 patch/apply.py "$framework" patch/DEV112-P006.zip \
      --rollback --route "$route" --stopped --owner-authorized \
      --receipt "$receipt_dir/apply.json" --receipt-sha256 "$receipt_sha" \
      > "$receipt_dir/rollback-audit.json"

Rollback applies to the framework and requires the same installation instance, the authentic receipt and the expected postimage. Plugin Manager updates have a separate lifecycle. Additional files outside the patch's guarded source members are preserved; managed files must match their expected hashes and modes. Atomicity is per file. After an interruption, retain receipts and the partial state and restore from backup; do not assume a whole-tree transaction or automatic continuation.

Depositing this delivery does not activate any existing installation.

## Source and acceptance

This delivery contains the completed required-API source recorded in ASSEMBLY.json and the exact payload recorded in patch/FILES.json. Earlier P006 archives remain retained. For an earlier P006 installation, use its own original helper, archive and authentic receipt to restore its admitted baseline before applying this cumulative release.

Acceptance uses the owner's finite eight-row risk matrix with independently accepted evidence reused where the source and behavior remain applicable. Prior failures and unexecuted checks remain identified as such. New managed payload is checked through isolated installation and rollback on both admitted baselines. The delivery acceptance record states the final decision; archive creation alone is not functional approval.

ORION 1.0.11 and SII 0.4.37 package bytes remain unchanged. Their separate Plugin Manager lifecycle is not rolled back by the framework helper. The owner's A02 inventory-before-implementation requirement is withdrawn.

The two shared cache/temp Configuration values remain an unresolved historical custody incident. Their original values are unavailable and have not been invented. This delivery does not restore preferences by trial and error or alter scientific data.
