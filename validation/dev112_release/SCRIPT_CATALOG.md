# DEV112 reduced-scope release tools

`python3 -I -B build.py REPOSITORY FULL_CLEAN_COMMIT NEW_SCRATCH_OUTPUT`
reads exacttracked Git objects, verifies P035 lineage/allowed source differences,
stages selected runtime/docs/resources and original/lossless plugin containers,
excludes mutable registries/userdata/history/test outputs, writes exact manifests
and deterministic full tar.gz, and reads its closure back. New RAID scratch only.
No module/seal/code regeneration, no scientific execution or installation.

`python3 distribution/install.py NEW_TARGET [--migrate-from OLD_TARGET --stopped]
[--config-source OLD_CONFIG --config-target NEW_CONFIG]`
verifies the offline bundle, refuses existing targets/symlinks, copies its full
framework, including CORE and ALWAYS modules, and invokes the unchanged official
Plugin Install API using install_worker.tcl for optional plugins ONLY. CORE/ALWAYS
never enter an install/update/registration plan, including migration.
Creates only fresh target-local registry through that API and local receipts.
Migration never writes the old installation, Configuration, Session/RAW or Library;
conflicts are named, not silently changed. No owner/live activation or default
Configuration generator. Logs/private installation state use a fresh private
sibling `.gxtxt-dev112-install-TARGETNAME`, outside framework/owner state under
the existing CORE diagnostics policy. A small receipt also lives in the new target.

Focused acceptance and final new-only publication tools will be registered before
use. Historical scripts are not executed unchanged. No P029–P035 campaign replay.

Builder implementation details: mandatory original Viewer026 SHA ded07ad9...1198
and Preview012 SHA57a0ae93...c5b2 are mechanically copied unchanged; no tests or
repackaging. Published originals are selected only by normalized complete file
set/byteSHA equality to acceptedGit, never filename/version alone. New module
ZIP wrappers preserve accepted payload/checksum bytes, with deterministic
0644/0755 fromGit executable intent. Literalcore1/missingcore, existing ALWAYS and the documented
geospatial freshInstall exception staybundled unchanged;62 optionalcore0 packages
useofficialAPI plan. All18 legacy model/instrument/analysisdefinition roots remain
bundled/unmanaged. Includes public examples/tools/docs/runtime assets and exact
P035 fiveGenerator+IRteachingLibrary originals/four optionalIRScientificLibraries;
these optional packages are listed for explicit normal owners, never auto-ingested.
No source/module/seal/Registry/activation fix. New sourcecommit must be clean and
contain only approved DEV112 version/TODO/prose/distribution-tool metadata changes
fromce349; all runtime behavior andmodule bytes remain accepted. Builder itself
and this catalog are explicitly shipped despite excluding historicalvalidation.
`python3 -I -B build.py --help` and a Python AST parse are source-only CLI/syntax
checks; full builds wait MAIN's reviewed cleancommit. No sourcecommit or SSD
publication is performed by the helper.

Final binding partition: allCORE and
existing ALWAYS (kind=acquisition OR !selectable, defaultselectable1) staybundled;
51core0 ALWAYS includes13selectable1 importers. Exact plan62optionalnormalinstalls,
102bundledmodules (44core1+6missing+51core0ALWAYS+1knownexception), plus18legacy
other types. No CORE/ALWAYS in the installer. Read-only source-roster/dependency
selfcheck may import build.py and call Objects/module_inventory/order_plugins
against ce349; no archive/staging, module execution, Registry or source writes.

The builder copies only canonicalP035 ACCEPTANCE_A.json,ACCEPTANCE_B.json,HANDOFF.md
from /srv/gxtxt/releases/dev111/patches/0035-ir-viewer-teaching-cache-bridge into
distribution/reused_p035, checking fixed SHA identities. These original public
receipts are reused evidence, not new functional claims. Sourceapproval accepts
only the seven explicit version/TODO/catalog metadata paths plus newINSTALL_DEV112,
newdistribution files and exactbuild.py/catalog; TODOaf36/PATCH000 and version-only
Tcl change are fixed. README/CHANGELOG/docs trees are not a broadchangeallowlist.

Candidate02 packaging-only doc selection audit: read exactGitce349 folder counts,
first headings of top-level docs/{development,reports} manuals and literal relative
MD/HTML resource links to decide finite historical campaign exclusions. No renderer,
module execution, source/doc rewriting or archive rebuilding untilMAINcommit.
Keep ordinary technical manuals/API docs and explicit reachable illustrations;
record excluded historical folders/link constraints in provenance.

Candidate02 finite doc selector (no general crawler): keep4topdevelopmentMD and
122topreportMD/HTML prose; raw11CHANGED_FILES TXT inventories, topJSON/patches,
and nested historical campaign folders under docs/development,reports,evidence
are excluded. Exact currentreference exceptions:2curve_workbench dev053 inlinePNG,
task210/ic_baseline_form/README.md (noinlineassets), and currentAPI-cited
MOLECULE_ACCEPTANCE.json. Current publicAPI/guides/developer andmodule manuals
remain unchanged. Historicaloperator-matrix screenshot chains are not followed;
manifest records intentionally omitted archival prooflinks and per-folder counts.

LATEST owner binding supersedes candidate02's62-install layout: all149 nonDemo
modules are expanded in framework; ONLY15Demo modules in a separate demos TAR.
Root distribution/module_packaging.json is the fixed purpose-reviewed15-ID policy.
Three authorized CORE lines, waveform module.ini digest and definitionDemo normal
package manifest are the only module source exceptions; geospatial Demo wrapper
adds only the existing published f875 documentation resource unchanged.
`python3 -I -B prepare_registry.py REPO CLEAN_COMMIT NEW_SEED_OUTPUT` stages100
nonDemo CORE/ALWAYS/legacy-module roots plus18other legacy types with49optional
paths absent, then invokes Root's import-safe migrate.worker and actual normal
Plugin Install API for49 nonDemo optional packages. Fresh private external state,
real clocks and current guards; no CORE/ALWAYS/Demo operations, development
registry copy or manufactured rows. Freezes only actual installed.ini bytes,
49payload byte/mode evidence, API log/plan and hash-bound seed_manifest.json.
`build.py REPO SAME_CLEAN_COMMIT NEW_OUTPUT --registry-seed SEED --registry-seed-sha256 HASH`
performs no API installation: verifies frozen successful seed identities/receipt,
restages149nonDemo exactsource plus49real-installed modes and rawregistry bytes;
outputs deterministic fullframework and separate15Demo artifacts. Same source +
same frozen real seed are reproducibility inputs; preparation timestamps are
truthful and never stubbed or claimed rerun-deterministic. No private prep state,
Configuration/cache/locks enter release. Full receipts are preserved/hashed.

Final Generator coverage (supersedes historical 38-count/optional-only notes):
all385 tracked runtime resources under session_generator_libraries remain exact,
including four source Library identities and44 distinct active Generator IDs.
The builder records their IDs/versions/descriptor SHA and full resource closure
in distribution/manifests/GENERATOR_INVENTORY.json. Two supplemental normal
Library originals remain explicit: geospatial1.0.1 (c4108476...) and P035
IRteaching1.0.0 (71338764...), alongside five original P035 standalone Generators
and four optional Scientific Libraries. Historical session_generator_packages
duplicates remain omitted with exact source-path count; no lost logical IDs,
automatic replacement, Generator installer, scientific regeneration or new API.
Geo1.0.0 remains only the separate Demo's original documentation resource.
Focused precommit source checks: Python AST parse and isolated -I -B --help for
both helpers; finite descriptor/ZIP metadata and container SHA reads only.
No preparation/build until MAIN commits the reviewed clean same-source input.
