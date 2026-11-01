# Registered Script Projects v1

Script Projects extend `SCRIPT_EXECUTION_API_v1`, its existing Registry and
managed Job supervisor. Ordinary single-file records retain `kind=script`.
Projects have `kind=project`, one qualified `user:ID` or `session:ID`, language,
semantic version, revision, entrypoint and an explicit manifest of UTF-8 source.

Host operations, under `::GX`:

- `scriptRegistryProjectSave scope id name language entrypoint files ?options? ?session?`
- `scriptRegistryProjectUpdate scope id expectedSha metadata entrypoint files ?session?`
- `scriptRegistryProjectFiles metadata`
- `scriptRegistryProjectExport reference destination ?session?`
- `scriptRegistryProjectImport scope id name archive ?options? ?session?`

`files` is a dictionary of normalized relative paths to UTF-8 source strings.
Only `.py` for Python or `.m` for Octave is admitted, at most 256 files, 4 MiB per
file and 16 MiB total. Paths cannot be absolute, traverse parents, contain
backslashes, symlinks, control characters or duplicate case-insensitive names.
Subfolders are supported. No source executes during admission or inspection.

Describe returns existing metadata plus `project_manifest`, `project_root`,
`project_files` (path to SHA/size/role), `admitted_sources`, `entrypoint`,
`entrypoint_sha256` and `project_sha256`. Existing `sha256` is the composite
project identity. Byte-only consumers must use `entrypoint_sha256`.
`project_revision` names the immutable revision directory. The manifest's
`gxtxt.script_project.v1` hash covers language, entrypoint and the ordered full
file/size/role/SHA closure using canonical JSON without the SHA field.

Save All validates and writes a complete new revision, then atomically replaces
one Registry metadata pointer. An exclusive update lock and expected SHA/revision
check refuse concurrent stale edits. Host metadata may additionally pin
`expected_revision`; ordinary Workspaces/Library always supply it to protect
same-source metadata updates. Failed new content does not publish partial
source. Older revisions remain immutable; Session assignment physically copies
the complete tree. Every Job independently freezes and verifies another complete
tree under its owned run directory. Launch and history inspection verify its
composite digest. Later Registry edits cannot retarget a historical Job.

Python imports admitted helpers/packages from the frozen project root. Octave
executes the named entrypoint and adds directories containing admitted function
sources; it preserves genuine file names and native stack attribution. These
runtimes retain their documented ordinary language capabilities and existing
Dataset/Bridge authorities. A project manifest is source admission, not an OS
sandbox or a grant of additional public capabilities.

Project Debug accepts `options.debug_breakpoints` as a dictionary from admitted
relative paths to positive physical lines. The immutable composite SHA pins
commands and breakpoints; Python bdb and native Octave stack frames retain actual
files. Single-file Debug keeps its original line-list interface. All ordinary
Job cancellation, resource limits, input binding and Publication rules apply.

Script Library lists both kinds and offers New Project, Import Project ZIP,
Export, Assign and Open Workspace. Each Python/Octave Workspace uses the common
file-aware Source Surface tab controller. Project menus add/rename/move/remove
files and select the entrypoint through the same whole-project update. Save All
commits all admitted source buffers together. Independent Scripts retain their
own Registry identities and execution. The file chooser above tabs exposes
long/overflowing identities; Ctrl+Tab and Ctrl+Shift+Tab cycle buffers. Close tab
and window review modified buffers with Save/Discard/Cancel.

Python project imports are pinned by the existing language adapter to the
admitted bytes and their real source paths. Conflicting already-loaded runtime
module names refuse execution; recognized explicit external source-loader or
`sys.path` mutation calls refuse project admission. Use admitted helpers/packages
or approved configured-runtime packages. Normal nested package entrypoints retain
relative import semantics. The manifest does not inspect scientific data files.

Portable ZIPs include digest-checked `registry.json` metadata (version, description,
manual/source schemas, explicit/required APIs, callables and inert arguments).
Import assigns the requested new scope/ID/name while retaining archive-source SHA
provenance. Sources and metadata are reviewed without executing code.

P033 additive import admission: `options.expected_language`, when supplied, is
exactly `Python` or `Octave`. The existing verified archive owner checks it before
creating the Registry record. A different language refuses and removes only its
temporary verified import, leaving existing records and sources unchanged. The
option is admission context and is never stored as portable Registry metadata.
Calls omitting it retain the existing language-from-manifest behavior. Editors
use this option to keep an import in their selected language without parsing ZIPs
themselves or creating then deleting an unwanted record.

Octave uses only manifest-managed project search directories. Recognized explicit
source/run loaders and import-path mutations are rejected during project
admission. Reserved native execution/path-owner filenames cannot be shadowed.
At runtime every admitted `.m` identity must resolve to its frozen file;
ambiguous basenames or a competing current-directory function refuse before
entrypoint execution. Use filename-correct helpers and configured runtime packages.
