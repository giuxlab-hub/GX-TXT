# GX-TXT DEV112 public distribution

This release is standalone. DEV111 patches do not need to be replayed.
All 149 non-demo modules, including every existing CORE and ALWAYS module,
are included. Their accepted scientific code and activation policies are retained.
The 49 normal independent modules retain the legitimate Plugin Install API seed
from release preparation; no mutable development registry is distributed.

## Choose an installation method

Use the graphical portable installer to choose a new folder, including a folder
in your home directory. It offers individual demo modules, public Generator
collections and examples. The default includes all offered components. Personal
configuration, Sessions, Libraries, cache and diagnostics remain within the
chosen prefix. Never overlay an existing installation.

Alternatively, install the Debian 13 amd64 `gxtxt` package using your normal
graphical package manager. It installs the actual application under `/opt/gx-txt`;
it is not an installer for a second application. `gxtxt-demos` and
`gxtxt-generators` are optional Debian add-on packages. APT resolves declared
dependencies and recommends important optional tools. Additional OCR languages,
scientific tools and their runtime paths remain configurable in GX-TXT.
The system launcher stores each user's data in their own home/XDG locations.

The main framework always includes ordinary non-demo modules. Demo installation
uses the existing Plugin Install API. CORE and ALWAYS behavior is unchanged.
Do not run a second instance during package or plugin maintenance.

## Public and private material

The public Generator collections contain 39 complete Generators. The additional
five complete IR teaching Generators, five original IR/NMR Scientific Library
packages and ten measured IR teaching Session/HTML archives are delivered in
the separate private owner workkit. All 44 Generator IDs are preserved across
the two deliveries. The public subset Library is explicitly versioned
`1.1.0-public1`; retained Generator code and payloads are unchanged.

Use **Install private material...** in the graphical installer's File menu or
the installed application-menu utility. Select the separate workkit archive and
the intended GX-TXT installation. The utility imports scientific and Generator
Libraries through their existing public Library Managers. It copies teaching
examples without executing or automatically opening Sessions. Private data is
not included in public Debian packages or the public portable installer.
The private workkit is for the owner's work and tests; it grants no redistribution
rights. Originals inside it retain their exact ZIP contents and SHA-256 identities.

## Migration and recovery

Install into a new prefix. Retain the previous installation unchanged until the
new one starts successfully. Back up personal Configuration, Sessions, Libraries
and independently installed packages before choosing migration. Follow the
existing `MIGRATION.md` and `RECOVERY.md`; scientific data must never be merged
by replacing a framework directory. Never copy a development registry into a
new installation. Use the existing Plugin and Library Managers for personal
packages. Removing system packages does not remove personal scientific data.

## Provenance and limitations

The accepted source is `8e637adff46306b5005297679166c09a1e9d36b8`, based on
accepted DEV111-P035 `ce34988db2c7500b60f7235b237b2fdb67e5d434`.
`manifests/PUBLIC_VARIANT.json` records this public data separation. The new
`manifests/files.json` describes this variant, not the earlier complete-data TAR.
Historical P035 reports are reused evidence, not new test claims.

Curve Digitizer Viewer 2.0.26 and Preview 0.1.12 are included unchanged.
Their original ZIPs retain their SHA-256 identities. Qualification remains
`OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST`. Only distribution
and normal package-lifecycle checks are performed. No scientific module campaign
is repeated. Existing REAL_UNVERIFIED scientific limitations remain unresolved.
