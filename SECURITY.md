# Safe validation source publishing

The `validation` branch distributes **test source**, not accepted scientific results, production Session databases or archived installation evidence.

## Do not include

- The two privately supplied document-extraction PDFs, their dependent generator and related fixtures.
- Personal/proprietary scientific records, captured Sessions, home directories, tokens, stored credentials, network shares, or system-specific service configuration.
- Historical mutable release deployment, rollback, delete/uninstall or user-installation migration scripts.
- Full `release_evidence` / `validation` archive dumps, supervisor databases, cached job results, screenshots containing private data or earlier assistant handoffs.

## Running scientific tests

A test can launch actual numerical processes and write new scientific data. Work only with an independently extracted test framework and **new, disposable** XDG/Job/Session directories. The optional runner keeps all outputs in a fresh temporary directory and refuses an active `current` installation path. Manual tests require the same precautions.

**No claim of an OS sandbox:** a Tcl, Python, Octave or native library process runs with the current user's normal permissions. Use OS-level isolation when running unfamiliar or externally contributed tests.

## What can be published

Small synthetic numerical fixtures, independent expected values, explicitly licensed upstream test references, public API calls, and reviewed test logic with a reproducible failure mode. Where upstream sources are confidential, publish independent synthetic substitutes rather than an original input or an encoded derivative of it.

A source-only publication is not proof of runtime PASS. Keep a clear separation between the public test, its platform/runtime prerequisites and actual verification receipts.
