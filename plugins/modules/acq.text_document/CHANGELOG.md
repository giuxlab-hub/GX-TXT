# 1.2.0 — DEV111-P031

Normal .puml/.plantuml inspection and import now use the shared CORE bounded
class/sequence parser and document.uml contract. Exact UTF-8 source, BOM, RAW
and line endings are preserved; unsupported syntax/encoding and Session-script
destination refuse. Metadata exposes the actual profile/family/source SHA.
Other document/source destinations and detection remain unchanged.

# 1.1.0 — Debian dev106

Unified public source/document, managed execution and scientific Viewer integration. See the module manual and dev106 acceptance ledger for exact tested scope and remaining limits.

# Changelog

## 1.0.4 — 2026-10-01

Separate import contract choice from detected or selected source language.
Python and other source files can be imported as either preserved text documents
or source-code Datasets. Declare ordered file chooser groups and external RAW
reference support through the standard Acquisition Handler descriptor.

## 1.0.3 — 2026-09-29

Apply the current Encoding and Language settings to source Preview through
the public Acquisition Handler `inspect` request. Preview and import now use
the same descriptor configuration without private CORE state access.

## 1.0.2 — 2026-09-29

Allow an imported Dataset preview before the Session's first Manifest save.
Persisted Dataset Metadata remains authoritative; optional notes are shown
when Session Inspection can open the saved Session.

## 1.0.1 — 2026-09-29

Use the public Acquisition Handler Dataset preview request's Session path for
persisted metadata and notes. The plugin no longer reads CORE's
`currentSession` variable or private Dataset registry fields. Imported source
bytes, detection behavior and Dataset schema are unchanged.

## 1.0.0 — 2026-09-28

Initial standalone text/source-code acquisition plugin for GX-TXT 0.9.8.09.
One source per Dataset; exact-byte preservation; standard batch and incremental
import; bounded read-only previews; language hints with explicit ambiguity and
manual override; strict encoding detection/selection; full streaming validation
and cancellation; persistent language/text metadata through public APIs.
Portable detection catalog/implementation are separated and documented for
future CORE extraction. No CORE modification, viewer, parser package or source
execution is required.
