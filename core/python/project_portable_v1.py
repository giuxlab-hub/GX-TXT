# SPDX-License-Identifier: GPL-3.0-or-later
"""Transport container only. Project persistence/transactions remain Tcl CORE-owned.
Nested Session ZIP validation and scientific serialization reuse Session Portable.
Bundled module snapshots are inert resources, never installed or executed by import.
"""
import hashlib, json, os, re, shutil, sys, tempfile, zipfile
from pathlib import Path, PurePosixPath
import session_portable_v1 as session
FORMAT='GXTXT-PROJECT-1'
MANIFEST='gxtxt-project.json'

def name(raw):
    if '\\' in raw or raw.endswith('/') or any(p in ('', '.', '..') for p in raw.split('/')):
        raise ValueError('Unsafe Project package path: '+raw)
    return session.safe_rel_text(PurePosixPath(raw))

def digest(p): return session.sha256_file(p)

def validate(archive, output=None):
    with tempfile.TemporaryDirectory(prefix='gxtxt-project-check-') as td, zipfile.ZipFile(archive) as z:
        entries={}
        for i in z.infolist():
            n=name(i.filename)
            if n in entries or session.zip_entry_is_symlink(i): raise ValueError('Duplicate or symbolic Project entry: '+n)
            entries[n]=i
        if MANIFEST not in entries: raise ValueError('Missing Project package manifest')
        if entries[MANIFEST].file_size>16*1024*1024: raise ValueError('Project manifest exceeds 16 MiB')
        def unique(pairs):
            d={}
            for k,v in pairs:
                if k in d: raise ValueError('Duplicate manifest key: '+k)
                d[k]=v
            return d
        m=json.loads(z.read(MANIFEST),object_pairs_hook=unique)
        if m.get('format')!=FORMAT: raise ValueError('Unsupported Project format')
        files=m['files']
        if set(entries)!={MANIFEST,*files}: raise ValueError('Project inventory does not match archive')
        if not isinstance(m['sessions'],list) or len(m['sessions'])>10000: raise ValueError('Invalid Experiment inventory')
        if not m.get('source_project_id'): raise ValueError('Missing source Project identifier')
        if 'source/project.ini' not in files or 'source/transfer.ini' not in files: raise ValueError('Missing Project metadata')
        directories=m.get('directories',[])
        if len(directories)!=len(set(directories)): raise ValueError('Duplicate Project directories')
        for n in directories:
            name(n)
            if n in files or not n.startswith(('resources/','dependencies/')): raise ValueError('Invalid Project directory: '+n)
            (Path(td)/n).mkdir(parents=True,exist_ok=True)
        eids=set(); paths=set()
        for r in m['sessions']:
            if not r['source_experiment_id'] or r['source_experiment_id'] in eids or r['archive'] in paths:
                raise ValueError('Duplicate or missing source Experiment identifier')
            if not re.fullmatch(r'sessions/[0-9]+\.zip',r['archive']): raise ValueError('Invalid Session package path')
            eids.add(r['source_experiment_id']);paths.add(r['archive'])
        if paths!={n for n in files if n.startswith('sessions/')}: raise ValueError('Session inventory mismatch')
        for n,r in files.items():
            name(n)
            if not (n.startswith(('source/','sessions/','resources/','dependencies/'))): raise ValueError('Unknown Project payload: '+n)
            i=entries[n]
            if i.file_size!=r['size'] or not re.fullmatch('[a-f0-9]{64}',r['sha256']): raise ValueError('Invalid Project file inventory: '+n)
            target=Path(td)/n;target.parent.mkdir(parents=True,exist_ok=True)
            h=hashlib.sha256()
            with z.open(i) as f,target.open('xb') as out:
                for b in iter(lambda:f.read(1024*1024),b''): h.update(b);out.write(b)
            if h.hexdigest()!=r['sha256']: raise ValueError('Project SHA-256 mismatch: '+n)
        transfer=session.simple_ini(Path(td)/'source/transfer.ini')
        if transfer.get('project',{}).get('id')!=m['source_project_id']:
            raise ValueError('Project source metadata disagrees with package')
        expected={f'experiment.{i}' for i in range(1,len(m['sessions'])+1)}
        if {k for k in transfer if k.startswith('experiment.')}!=expected:
            raise ValueError('Project transfer inventory is not contiguous')
        for i,r in enumerate(m['sessions'],1):
            if r['archive']!=f'sessions/{i}.zip' or transfer[f'experiment.{i}'].get('experiment_id')!=r['source_experiment_id']:
                raise ValueError('Project transfer identifiers disagree')
            sm,_=session.validate_archive(Path(td)/r['archive'])
            if int(sm['package'].get('external_dependency_count','0')): raise ValueError('Incomplete Project: unresolved external Session resources')
            # Organizational links must agree with the enclosing Project membership.
            with zipfile.ZipFile(Path(td)/r['archive']) as nested:
                mf=Path(td)/'member.ini';mf.write_bytes(nested.read('session/metadata/manifest.ini'))
                # ZIP hashes alone cannot detect a missing registered scientific payload.
                # Cross-check canonical registry references against the validated Session
                # inventory; the Tcl exporter additionally uses the public Payload reader.
                if 'session/metadata/datasets.ini' in nested.namelist():
                    registry=Path(td)/'datasets.ini';registry.write_bytes(nested.read('session/metadata/datasets.ini'))
                    payloads={rec['path']:rec['sha256'].lower() for sec,rec in sm.items() if re.fullmatch(r'file\.\d+',sec)}
                    for sec,rec in session.simple_ini(registry).items():
                        if not sec.startswith('dataset.') or 'id' not in rec: continue
                        relative=name(rec.get('path',''))
                        if rec['id']!=sec[len('dataset.'):] or payloads.get(relative)!=rec.get('canonical_sha256','').lower():
                            raise ValueError('Broken canonical Dataset reference: '+sec)
            link=session.simple_ini(mf).get('project_link',{})
            if link.get('project_id')!=m['source_project_id'] or link.get('experiment_id')!=r['source_experiment_id']:
                raise ValueError('Project/Session identifiers disagree')
        if output is not None:
            if output.exists(): raise ValueError('Project extraction destination already exists')
            shutil.copytree(td,output)
            (output/'gxtxt-project.json').write_text(json.dumps(m,ensure_ascii=False))
        return m

def export(spec, archive, framework):
    transfer=session.simple_ini(spec/'source/transfer.ini')
    p=transfer['project'];root=Path(p['storage_path']).resolve();records=[];excluded=[];deps=set()
    for key,rec in transfer.items():
        if key.startswith('experiment.'):
            index=int(key.split('.')[1]);a=f'sessions/{index}.zip'
            sm,_=session.validate_archive(spec/a)
            if int(sm['package'].get('external_dependency_count','0')): raise ValueError('Incomplete Project: resolve external resources before export')
            for sec,d in sm.items():
                if sec.startswith('dependency.'): deps.add(d['module_id'])
            records.append(dict(archive=a,source_experiment_id=rec['experiment_id'],name=rec['experiment_name']))
            excluded.append(Path(rec['session_path']).resolve())
    # Save Project-owned resources outside registered Sessions, including hidden files.
    # Reject unresolvable symlink trees: silently omitting resources is not portable.
    def addtree(src,dst,omit=()):
        for f in sorted(src.rglob('*')):
            if any(f==q or q in f.parents for q in omit): continue
            if f.is_symlink(): raise ValueError('Project resource symlink must be materialized before export: '+str(f))
            if f.is_dir(): (dst/f.relative_to(src)).mkdir(parents=True,exist_ok=True)
            if f.is_file():
                target=dst/f.relative_to(src);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
    if root.is_dir(): addtree(root,spec/'resources',excluded+[root/'project.ini'])
    seen=set()
    while deps-seen:
        mid=sorted(deps-seen)[0];seen.add(mid)
        if not re.fullmatch('[A-Za-z0-9_.-]+',mid): raise ValueError('Unsafe dependency identifier')
        module=framework/'plugins/modules'/mid
        if not (module/'module.ini').is_file(): raise ValueError('Missing module dependency: '+mid)
        addtree(module,spec/'dependencies/modules'/mid)
        meta=session.simple_ini(module/'module.ini').get('meta',{})
        deps.update(session.split_ids(meta.get('depends','')))
    m=dict(format=FORMAT,source_project_id=p['id'],carrier_installation=p['carrier_installation'],sessions=records,
           dependencies=sorted(seen),directories=[name(f.relative_to(spec).as_posix()) for f in sorted(spec.rglob('*')) if f.is_dir() and f.relative_to(spec).parts[0] in ('resources','dependencies') and len(f.relative_to(spec).parts)>1],files={})
    for f in sorted(spec.rglob('*')):
        if f.is_file():m['files'][name(f.relative_to(spec).as_posix())]=dict(size=f.stat().st_size,sha256=digest(f))
    archive.parent.mkdir(parents=True,exist_ok=True)
    # Exclusive temporary name + no-clobber publication; an existing package is never replaced.
    fd,tmp=tempfile.mkstemp(prefix='.gxtxt-project-',dir=archive.parent);os.close(fd);temp=Path(tmp)
    try:
        with zipfile.ZipFile(temp,'w',zipfile.ZIP_DEFLATED,allowZip64=True) as z:
            z.writestr(MANIFEST,json.dumps(m,ensure_ascii=False,sort_keys=True))
            for n in m['files']:z.write(spec/n,n)
        validate(temp)
        os.link(temp,archive)
    finally:temp.unlink(missing_ok=True)
    return m

def main():
    op=sys.argv[1]
    if op=='export':m=export(Path(sys.argv[2]),Path(sys.argv[3]),Path(sys.argv[4]));a=Path(sys.argv[3])
    else:
        a=Path(sys.argv[2]);m=validate(a,Path(sys.argv[3]) if op=='extract' else None)
    session.emit(dict(archive=str(a),sha256=digest(a),experiment_count=str(len(m['sessions'])),dependency_count=str(len(m['dependencies'])),file_count=str(len(m['files']))))
if __name__=='__main__':
    try:main()
    except Exception as e:print('Project Portable error: '+str(e),file=sys.stderr);sys.exit(1)
