# Tektronix Current Log importer changelog

SPDX-License-Identifier: GPL-3.0-or-later

## Distribution status — GX-TXT v0.9.7.1

- Promoted `acq.tektronix_current_log` to explicit protected CORE status.
- Changed runtime availability from non-selectable `ALWAYS` to selectable `CORE / OFF`.
- The importer remains disabled by default and must be enabled by the user when needed.
- Scientific/import behavior and plugin version remain unchanged (`version=2`).

## Version 2

- Acquisition Handler Plugin API v1 implementation for Tektronix current-log files.
- Framework-owned batch/incremental lifecycle, Preview/Variables mapping, RAW snapshot, SHA-256 and Dataset Registry integration.
