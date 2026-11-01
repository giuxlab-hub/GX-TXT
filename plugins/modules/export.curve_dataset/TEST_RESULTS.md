# Stabilization acceptance — GX-TXT dev094

SPDX-License-Identifier: GPL-3.0-or-later

PASS evidence is in framework `docs/reports/dev094_evidence`; fresh-extracted
artifact gates and immutable outputs are recorded in the final release receipt
under `_evidence_stabilization_dev094/package-suite`. Tests use disposable Sessions
and real local Debian Xorg :1 for GUI checks. Failed development iterations remain
separate and are not counted as acceptance.

PASS: 20,000-row source reduced to 16 display points publishes 1850 independently checked exact rows; dtypes/units/lineage/provenance/source SHA unchanged; above-2^53 int64 and NaN/Inf rows exact; declared gaps match sync/async sampled reopening; collision/bad ID/empty/stale source/document generation/revision/Session/unsupported-unit rejection without phantom output; real GUI action, cancel, publication, normal Preview and Session reopen; normal install/enable/disable/uninstall/reinstall.
