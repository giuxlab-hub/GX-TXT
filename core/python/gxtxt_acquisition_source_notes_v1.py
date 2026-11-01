# SPDX-License-Identifier: GPL-3.0-or-later
"""Typed Acquisition project adapter to the existing SourceAuthoring owner.

No note store, renderer, source Dataset or authorization registry is introduced.
The caller holds the existing project lock/CAS and publishes only the pointer.
"""
import base64
import copy
import hashlib
import gxtxt_acquisition_project_v1 as model
import viewer_source_authoring_v1 as existing

authoring=existing.authoring
KEY=existing.KEY

def descriptors(meta,files):
    languages={row['relative']:row['language'] for row in model.roster(meta)}
    return {name:dict(language='cpp' if languages[name]=='cpp' else 'python',source_sha256=hashlib.sha256(raw).hexdigest())
            for name,raw in files.items() if languages[name] in {'cpp','Python'}}

def validate(project,meta,files,portable=None):
    value=existing.pointer(meta)
    if value is None:
        if portable:raise authoring.AuthoringError('Undeclared Acquisition Source Note payload')
        return
    state=authoring._validated_payload(portable,value) if portable is not None else authoring.read(project,value)
    supported=descriptors(meta,files)
    for name,record in state['manifest']['files'].items():
        if name in files and (name not in supported or record['language']!=supported[name]['language']):
            raise authoring.AuthoringError('Source Note language differs from its actual registered project source')

def resolve(project,meta,files,payload):
    name=existing.resolve(project,meta,files,payload.get('relative'),payload.get('file_key',''),payload.get('owner_key',''))
    if name not in files:raise authoring.AuthoringError('Choose a registered Acquisition source/header/helper')
    if name not in descriptors(meta,files):
        raise authoring.AuthoringError('Tcl helper notes are unavailable in the existing SourceAuthoring owner; helper source remains editable')
    return name

def projection(project,meta,files,payload):
    name=resolve(project,meta,files,payload);value=existing.pointer(meta)
    state=authoring.read(project,value);record=state['manifest']['files'].get(name) if state['manifest'] else None
    note=authoring.file_note(project,value,name) if record else None
    return dict(status='SAVED',note_state='saved' if note is not None else 'uncreated',
        owner_key=value['owner_key'] if value else '',file_key=record['file_key'] if record else '',relative=name,
        language=descriptors(meta,files)[name]['language'],source_sha256=hashlib.sha256(files[name]).hexdigest(),
        source=files[name].decode('utf-8'),note_base64=base64.b64encode(note.encode('utf-8')).decode('ascii') if note is not None else '',
        created=note is not None,authoring_revision=value['revision'] if value else '',
        project_id=value['owner_key'] if value else '',project_name=meta['module_id'],
        asset_snapshots={key:dict(row,schema='gxtxt.source_asset.v1',blob_key=row['sha256']) for key,row in (record or {}).get('assets',{}).items()})

def prepare(project,meta,files,payload):
    op=payload['operation'];name=resolve(project,meta,files,payload);value=existing.pointer(meta)
    if op not in {'note_identity','note_write'}:raise authoring.AuthoringError('Unknown Source Note mutation')
    if payload.get('expected_source_sha256')!=hashlib.sha256(files[name]).hexdigest():raise authoring.AuthoringError('Source changed before saving its note')
    if payload.get('expected_authoring_revision','')!=(value['revision'] if value else ''):raise authoring.AuthoringError('Source Note owner revision changed')
    updates={}
    if op=='note_write':
        encoded=payload.get('note_base64')
        if not isinstance(encoded,str) or len(encoded)>5592408:raise authoring.AuthoringError('Encoded note exceeds 4 MiB decoded bound')
        try:raw=base64.b64decode(encoded,validate=True);text=raw.decode('utf-8')
        except (ValueError,UnicodeError) as error:raise authoring.AuthoringError('Source Note requires base64 UTF-8 text') from error
        if len(raw)>authoring.MAX_NOTE_BYTES or '\0' in text:raise authoring.AuthoringError('Source Note exceeds 4 MiB or contains NUL')
        updates[name]=text
    assets=None
    if 'asset_plan' in payload:
        import source_asset_codec_v1 as codec
        plan=payload['asset_plan']
        if not isinstance(plan,dict) or set(plan)!={'directory','index_sha256','index_size'}:raise authoring.AuthoringError('Expected a consumed CORE Source Note asset plan')
        assets={name:codec.read_plan(plan['directory'],plan['index_sha256'],plan['index_size'])}
    pointer=authoring.prepare(project,value,descriptors(meta,files),updates,asset_updates=assets)
    updated=copy.deepcopy(meta);updated['provenance'][KEY]=pointer
    return updated

def source_change(project,meta,files,candidate,next_files,renames):
    old=existing.pointer(meta)
    if existing.pointer(candidate)!=old:raise authoring.AuthoringError('Source Note pointers cannot be authored as raw metadata')
    if old is None:return candidate
    before=descriptors(meta,files);after=descriptors(candidate,next_files)
    moves={a:b for a,b in renames.items() if a in before and b in after}
    pointer=authoring.prepare(project,old,after,renames=moves)
    updated=copy.deepcopy(candidate);updated['provenance'][KEY]=pointer
    return updated

def import_into(project,meta,files,payload):
    old=existing.pointer(meta)
    if old is None:
        if payload:raise authoring.AuthoringError('Undeclared Source Note import content')
        return meta
    authoring._validated_payload(payload,old)
    updated=copy.deepcopy(meta)
    updated['provenance'][KEY]=authoring.import_payload(project,payload,descriptors(meta,files))
    return updated
