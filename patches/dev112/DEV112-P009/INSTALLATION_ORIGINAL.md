# Installation and rollback

Use the accepted archive and its matching integrity-bound installer. Final
validation and checksums are supplied with the complete delivery.

Verify the delivered SHA256SUMS and retain the original delivery outside the
target installation. The framework version remains `0.9.8.10-dev-112`; its
separate patch marker becomes `009`.

Supported exact starting states are pristine DEV112 Release 2 and the accepted
cumulative post-P005, P006 r5, P007 and P008 deliveries. P008 source is
`f691b0f6e1016cb9af3db30ba3d1c8b5ea91429c`. The installer verifies complete
managed bytes/modes and refuses a modified or unidentified starting state.
Never repair an identity refusal by deleting local scientific data or bypassing
the guard. Preserve the refusal diagnostic and reconcile the actual source.

Extract the release package to a separate directory. The archive's apply.py and
FILES.json are a matched, integrity-bound pair. Check a stopped target first:

```sh
python3 -I -B apply.py /absolute/GX-TXT DEV112-P009.zip --check
```

Close applications and workers using this target before an authorized upgrade.
The acknowledgement flags do not detect or stop processes. Keep the receipt
outside the framework and retain successful stdout separately:

```sh
python3 -I -B apply.py /absolute/GX-TXT DEV112-P009.zip \
  --apply --stopped --owner-authorized --receipt /safe/new-p009-receipt.json \
  > /safe/p009-apply-audit.json
```

Confirm the final check and marker, and retain the exact receipt SHA printed in
the successful apply audit. Sessions, Configuration and unrelated user files
are preserved. The receipt identifies the actual source route and installation;
do not move it to another installation or edit it.

Rollback requires the same archive, stopped authorized target, authentic complete
receipt and independently retained exact receipt SHA from the apply audit:

```sh
python3 -I -B apply.py /absolute/GX-TXT DEV112-P009.zip \
  --rollback --stopped --owner-authorized --route post-p008 \
  --receipt /safe/new-p009-receipt.json --receipt-sha256 RECEIPT_SHA256
```

Use the actual recorded route: `r2`, `post-p005`, `post-p006-r5`, `post-p007`
or `post-p008`. Rollback restores that route's original managed bytes/modes and
removes only files newly introduced by P009. A modified final source, forged or
mismatched receipt is refused. Preserve interrupted transaction receipts and
diagnostics; do not rerun a mutation blindly.

Optional MCP installation on the supported Debian/Python architecture is a
separate explicit operation using the supplied versioned .deb. Follow the
framework integrations/mcp/README.md for local initialization, selected framework
verification, grants and start/stop. It defaults OFF, creates no clients and
activates no user service. Its removal retains user configuration and scientific
Sessions. Stop only the optional adapter before removal; accepted managed Jobs
remain owned by the original Supervisor.

Install Guides through the ordinary Plugin Manager/Guides interface. Compatibility
notices are advisory; package integrity, relative paths and data-only validation
remain mandatory. Guide removal affects the selected package, not scientific
Sessions or unrelated installed parts.
