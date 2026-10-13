# Installation Identity API v1 (dev082)

SPDX-License-Identifier: GPL-3.0-or-later

CORE creates a random UUID on normal startup. Tcl readers are
`installationIdentityInfo`, `installationIdentityCurrent`, `installationIdentityHistory`.
Script Bridge Python/Octave discovery exposes `INSTALLATION_IDENTITY_API_v1`
operations `info`, `current`, `history`. There is no administrative setter in the
service map. History returns ordered records: `id`, `previous`, `order`, UTC `date`,
`reason`. Info adds `authority`, `diagnostic`, `api_id`, `version`, `current`.

The host deployment anchor is `GXTXT_INSTALLATION_ROOT/identity` when explicitly
configured. Otherwise it is a hidden sibling `.gxtxt-installation-<deployment-name>/identity`
of the normalized framework directory. The installed `current/gxtxt` path is stable
through release replacements. Two different deployment paths obtain different ledgers,
even under one OS account. For version-named development/extracted trees, set an
explicit common installation root to simulate upgrades of one instance. Independent
installations must use distinct anchors; copying a release does not copy a ledger.
Keep the anchor with installation backups; moving an installation requires retaining
its anchor or explicitly setting its original root. Ordinary preference reset and
Session changes never touch the authority. No hardware or personal identifier is used.

Configuration → Installation Identity shows current/history and offers deliberate
Rotate / Regenerate with reason and native confirmation. Mutation lives only in the
host `::GX::InstallationIdentity` implementation; Tcl same-user code is not sandboxed.
This is practical lifecycle integrity, not cryptographic authentication.

The Python stdlib host helper uses an OS lock, validated SHA-256 envelope, fsynced
atomic replacement, previous-history backup and a durable pending commit decision.
Concurrent startup issues once. Interrupted rotations recover the longest verified
prefix-compatible history. Corrupt files are quarantined when verified recovery exists;
absent valid recovery and divergent histories produce explicit startup errors without
issuing a replacement or fabricating continuity. A retained initial temporary write
also requires recovery rather than silent reissuance. Hashes attest bytes, not creators.
Durability depends on the host filesystem and operating system; callers should use the supported installation recovery operations and maintain independent backups.

The installation identity API remains authoritative for generation and recovery of instance identifiers. Scientific provenance uses this authority through its documented CORE interfaces.
