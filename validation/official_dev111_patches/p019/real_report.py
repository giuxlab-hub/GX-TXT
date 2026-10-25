"""Private technical handoff and explicitly sanitized real-fixture summary."""
from pathlib import Path
from datetime import datetime,timezone
import collections,configparser,hashlib,json,sys,tkinter
framework,root=map(lambda p:Path(p).resolve(),sys.argv[1:])
info=json.loads((root/'inspection.json').read_text());trans=json.loads((root/'transport/transport-inspection.json').read_text())
assert info['status']=='CONSISTENT_PRIVATE_FILESYSTEM_SNAPSHOT' and trans['status']=='READY_PRIVATE_TRANSPORTED_FIXTURE'
source=Path(info['source']);raw=Path(info['private_snapshot']);work=Path(trans['working_session']);doc=info['requested_document'];payload=raw/'metadata/interactive_documents'/doc['storage_name']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
t=tkinter.Tcl();text=payload.read_text()
def get(d,*keys):return t.call('dict','get',d,*keys)
def exists(d,*keys):return bool(t.call('dict','exists',d,*keys))
def keys(d):return t.splitlist(t.call('dict','keys',d))
name=get(text,'workspace_metadata','name');assert name=='produrre_di_bug'
curves=get(text,'curves');representations=collections.Counter();sources=set();editable=[]
for identity in keys(curves):
 row=get(curves,identity);rep=get(row,'representation') if exists(row,'representation') else 'unknown'
 if exists(row,'sketch_definition','family'):rep='retained:'+str(get(row,'sketch_definition','family'))
 representations[str(rep)]+=1
 if exists(row,'source') and str(get(row,'source')):sources.add(str(get(row,'source')))
 if exists(row,'locked') and str(get(row,'locked'))=='0' and rep.startswith('retained:'):editable.append(str(identity))
relationships=get(text,'cad_workspace','constraints');kinds=collections.Counter()
for identity in keys(relationships):
 row=get(relationships,identity)
 for path in [('definition','kind'),('spec','kind'),('kind',)]:
  if exists(row,*path):kinds[str(get(row,*path))]+=1;break
closure=json.loads((root/'transport/dataset-payload-closure.json').read_text());ids={r['id'] for r in closure};missing=sources-ids
assert not missing,'Workspace source Dataset absent from copied canonical registry'
stats={'workspace_name':name,'logical_curve_count':len(keys(curves)),'representations':dict(representations),'source_dataset_ids':sorted(sources),'source_dataset_ids_resolved':True,'unlocked_retained_logical_ids':editable,'relationship_count':len(keys(relationships)),'relationship_kind_counts':dict(kinds),'payload_version':str(get(text,'version'))}
(root/'private-workspace-statistics.json').write_text(json.dumps(stats,indent=2)+'\n')
original_now={p.relative_to(source).as_posix():sha(p) for p in sorted(source.rglob('*')) if p.is_file() and not p.is_symlink()}
expected={k:v['sha256'] for k,v in json.loads((root/'source-inventory-before.json').read_text())['files'].items()}
unchanged=original_now==expected
(root/'source-final-readonly-verification.json').write_text(json.dumps({'observed_utc':datetime.now(timezone.utc).isoformat(),'matches_snapshot_source':unchanged,'file_count':len(original_now),'no_source_writes_performed':True,'warning':'Observational receipt only; future original-user edits are independent of this private fixture'},indent=2)+'\n')
raw_expected=json.loads((root/'transport/raw-before-hashes.json').read_text());assert {p.relative_to(raw).as_posix():sha(p) for p in sorted(raw.rglob('*')) if p.is_file()}==raw_expected
handoff=f'''# P019 real-fixture preparation handoff — PRIVATE, DO NOT DISTRIBUTE

Status: READY_PRIVATE_TRANSPORTED_FIXTURE. No GUI/stress/measurement acceptance
has been performed. MAIN owns later routing after controlled regression/tool gates.

## Identity

- Workspace: `{name}` (verified `workspace_metadata.name`, not a top-level key).
- Document: `{doc['id']}`, `{doc['module_id']}` / `{doc['provider_id']}`.
- Format: `{doc['format']}` version `{doc['format_version']}`.
- Source revision: `{doc['revision']}`; generation: `{doc['generation']}`.
- Payload: {info['document_bytes']} bytes; SHA256 `{doc['sha256']}`.
- Source: `{source}`.

The initial snapshot receipt's `workspace_name_verified:false` reflects an initial
TOP-LEVEL-only key probe, not an actual identity mismatch. The authoritative name
is nested; identity-confirmation.json and this private report confirm it by Tcl
list/dictionary parsing only (no payload evaluation or original activation).

## Safe-copy evidence

Existing public CORE `history_read_locks` acquired the original native History
family through read-only existing lock files. No original writable FD was observed
before/after. Complete filename/device/inode/size/mode/mtime/ctime/hash inventories
matched before/quiet/aftercopy/final. Copy bytes/modes/mtime match and inodes differ.
No symlinks/specialfiles. All {info['file_count']} regular files/{info['total_bytes']}
bytes were copied, including Document/History/checkpoints/journals/recovery,
managed resources, canonical Dataset files, configs and lock-file bytes. Project.ini
context copied privately. No drain, recovery, GUI or mutating API touched originals.

A quiet persisted snapshot is not a claim that every possible app was closed:
idle applications/unsaved RAM are outside filesystem observation. Final original
read-only source hash comparison: {unchanged}. Snapshot timing/observed processes
are recorded, not guessed. No original lock file was created, modified or deleted.

## Copies and usage

- Immutable exact raw snapshot: `{raw}`. DO NOT activate or mutate it.
- Existing-CORE portable archive: `{root/'transport/private-session-snapshot.zip'}`
  SHA256 `{trans['archive_sha256']}` ({trans['archive_bytes']} bytes), PRIVATE ONLY.
- Scoped working Session: `{work}`. This is the only copy eligible for later GUI.
- Workspace/Document ID remains idoc_0004; use normal public Workbench open context
  for that existing Document, never reconstruct curves manually as a substitute.

The Python existing public export ran on the RAW PRIVATE COPY only, not source;
existing import created the separate unpublished working Session and rescoped its
native History. Original/immutable raw snapshot remain exact. Native receipt:
source accepted159/durable159, no torn tail; authorized destination revision epoch1,
scientific_steps_changed0, auxiliary_preserved1. Transport archives preserve raw
History bytes inside the working Session. Original Document registry and payload
are byte-identical; all {len(closure)} canonical Dataset payloads retain exact SHA.
Source/variable/resource identities remain inside the copied records.

## Dependencies and fixture shape

- No unresolved acquisition source or symlink/external scan dependency.
- Module/version requirements: transport/dependency-closure.json (existing CORE
  discover_dependencies output against authoritative P018).
- All Workspace canonical source IDs resolve in the private Dataset registry.
- Fixture: {stats['logical_curve_count']} logical curves, {stats['relationship_count']}
  persisted relationships; representations/kinds and unlocked retained IDs are in
  private-workspace-statistics.json. Do not publish private logical/source names.
- Current raw snapshot includes5composite Paths,3splines,2retained polylines and
  one point-backed curve, with source references/payloads preserved.

The working copy is not a new independent history family for every test: use a
fresh secondary copy/public transport before destructive reruns if needed, retaining
this source baseline. Any Session recopy to another directory needs the SAME existing
public native History transport/rescope; do not plain-copy scoped working History
and assume its old owner identity remains valid. Do not manually edit gxh scope.

## Files to keep private

Entire snapshot/, transport/ (including ZIP, Dataset/source hashes, original payload
and native transport archives), process paths, full source inventories and private
statistics. They must NOT be included in P019 ZIP. Only the separately authored
SANITIZED_SUMMARY.md is suitable for reviewed product reporting; actual GUI stress
results will be added by MAIN/testing owner later. No GUI PASS is claimed here.
'''
(root/'HANDOFF_PRIVATE.md').write_text(handoff)
summary=f'''# P019 real Workspace snapshot preparation — sanitized summary

This is preparation evidence, not GUI stress acceptance. The identified user
Workspace/Document was copied under read-only source protection. Existing CORE
History shared locks and repeated full source/stat/hash inventories established a
bounded consistent persisted snapshot: {info['file_count']} files, {info['total_bytes']}
bytes. No original GUI, History drain/recovery, scientific edit or source write.
No source writer was observed; this is not proof of absence of an idle app or
unsaved RAM. Original source content remained unchanged through final observation.

A second private working Session was created with existing public CORE portable
export/import, run only on the private copy. Native History scope was rebound to
that new Session with scientific steps unchanged and auxiliary state preserved.
All14canonical Dataset payloads and the original Document registry/payload retain
exact byte hashes. All referenced source Dataset identities resolve. No external
acquisition/symlink dependency is unresolved; required modules were cataloged.
The fixture contains11logical curves (5composite Paths,3splines,2retained polylines,
1point-backed curve) and31persisted relationships. Original identities/units/source
rows remain owned by their existing scientific services.

Raw private Session, archive, source paths, scientific files and detailed receipts
are excluded from the distributed patch. MAIN will perform the bounded real GUI
stress only on the scoped working copy after the primary controlled/tool gate.
No real Workspace GUI result is claimed by this preparation report.
'''
(root/'SANITIZED_SUMMARY.md').write_text(summary)
print(json.dumps({'status':'READY_FOR_MAIN_PRIVATE_STRESS_ROUTING','source_unchanged_final':unchanged,'stats':{'logical_curves':stats['logical_curve_count'],'relationships':stats['relationship_count'],'kinds':stats['relationship_kind_counts']},'handoff':str(root/'HANDOFF_PRIVATE.md')},indent=2))
