"""Script Registry v1 whole-project manifest and integrity primitives.

No source execution, dependency installation or scientific data access.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import ast,hashlib,json,os,re,shutil,sys,zipfile,uuid
import importlib.abc,importlib.machinery
from pathlib import Path,PurePosixPath
from script_api_declarations import discover,discover_parameters,tcl
SCHEMA='gxtxt.script_project.v1'
MAX_FILES=256
MAX_BYTES=16*1024*1024
PORTABLE_FIELDS={'name','version','description','explicit_apis','required_apis','default_arguments','parameters','callables','source_authoring_v1'}

def sha(data):return hashlib.sha256(data).hexdigest()
def relative(value,language):
    if not isinstance(value,str) or not value or len(value)>240 or '\\' in value or ':' in value or any(ord(c)<32 for c in value):raise ValueError('Invalid project relative path')
    path=PurePosixPath(value)
    if path.is_absolute() or str(path)!=value or any(p in {'.','..'} or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]*',p) for p in path.parts):raise ValueError('Project paths must be normalized relative identifiers')
    if path.suffix != ('.py' if language=='Python' else '.m'):raise ValueError('Project admits only language source files')
    return value

def manifest(language,entrypoint,files):
    if language not in {'Python','Octave'}:raise ValueError('Project language must be Python or Octave')
    relative(entrypoint,language)
    if not 1<=len(files)<=MAX_FILES or entrypoint not in files:raise ValueError('Project requires admitted entrypoint and 1..256 files')
    records=[];seen=set();prefixes={};total=0;apis=set();parameters={}
    for name,data in sorted(files.items()):
        relative(name,language)
        if name.casefold() in seen:raise ValueError('Case-colliding project path')
        seen.add(name.casefold());total+=len(data)
        for n in range(1,len(PurePosixPath(name).parts)+1):
            prefix='/'.join(PurePosixPath(name).parts[:n]);fold=prefix.casefold()
            if fold in prefixes and prefixes[fold]!=prefix:raise ValueError('Case-colliding project directory')
            prefixes[fold]=prefix
        if len(data)>4*1024*1024 or total>MAX_BYTES:raise ValueError('Project source size exceeds bounds')
        # Parse an optional UTF-8 signature without changing admitted bytes,
        # sizes, hashes or the source snapshot retained below.
        source=data.decode('utf-8-sig')
        if '\x00' in source:raise ValueError('Project source contains NUL')
        if PurePosixPath(name).stem.startswith('gxtxt_') or PurePosixPath(name).stem=='gxtxt':raise ValueError('Project source cannot shadow reserved GX-TXT runtime modules/functions')
        if language=='Python':
            for node in ast.walk(ast.parse(source,filename=name)):
                if not isinstance(node,ast.Call):continue
                call=ast.unparse(node.func)
                if call in {'sys.path.append','sys.path.insert','sys.path.extend','sys.path.remove','sys.path.clear','importlib.util.spec_from_file_location','importlib.machinery.SourceFileLoader','runpy.run_path'}:
                    raise ValueError(f'{name}:{node.lineno}: external source loaders/import-path mutation are outside the admitted project; add a manifest source or use the configured runtime packages')
        if language=='Octave':
            if PurePosixPath(name).stem in {'source','run','addpath','rmpath','path','cd','which','exist','fileparts','canonicalize_file_name','dbstop','jsondecode','fileread','sprintf'}:raise ValueError('Project file shadows a native execution/path owner')
            # Native Octave resolves the leading function by its real filename.
            code=re.sub(r'(?m)^\s*[%#].*$', '', source).lstrip()
            function=re.match(r'function\s+(?:(?:\[[^\]]*\]|[A-Za-z_]\w*)\s*=\s*)?([A-Za-z_]\w*)',code)
            if function and function.group(1)!=PurePosixPath(name).stem:raise ValueError(f'Octave function name must match {name}')
        try:apis.update(discover(source,language,name,project_policy=True))
        except ValueError as exc:raise ValueError(f'{name}: {exc}') from exc
        for key,value in discover_parameters(source,language,name).items():
            if key in parameters:raise ValueError(f'Duplicate project parameter {key} in {name}')
            value['source_file_sha256']=sha(data)
            parameters[key]=value
        records.append(dict(path=name,sha256=sha(data),size=len(data),role='entrypoint' if name==entrypoint else 'source'))
    result=dict(schema=SCHEMA,language=language,entrypoint=entrypoint,files=records)
    result['sha256']=sha(json.dumps(result,sort_keys=True,separators=(',',':')).encode())
    return result,sorted(apis),parameters

def safe_read(root,name):
    path=root
    if root.is_symlink() or not root.is_dir():raise ValueError('Project root must be a regular directory')
    for part in PurePosixPath(name).parts:
        path=path/part
        if path.is_symlink():raise ValueError('Project symlinks are forbidden')
    if not path.is_file():raise ValueError(f'Missing project file: {name}')
    if path.stat().st_size>4*1024*1024:raise ValueError('Source exceeds bounds')
    return path.read_bytes()

def verify(root):
    root=Path(root)
    if root.is_symlink() or root.parent.is_symlink() or not root.is_dir():raise ValueError('Unsafe project revision directory')
    path=root/'manifest.json'
    if path.is_symlink() or path.stat().st_size>262144:raise ValueError('Unsafe project manifest')
    declared=json.loads(path.read_text())
    if declared.get('schema')!=SCHEMA or not isinstance(declared.get('files'),list) or not 1<=len(declared['files'])<=MAX_FILES:raise ValueError('Unsupported/bounded project manifest required')
    files={};base=root/'files'
    for item in declared['files']:
        name=relative(item['path'],declared['language'])
        if name in files:raise ValueError('Duplicate manifest file')
        files[name]=safe_read(base,name)
    actual,apis,parameters=manifest(declared['language'],declared['entrypoint'],files)
    if actual!=declared:raise ValueError('Project manifest SHA/size/role closure differs')
    actual_paths=set()
    for parent,dirs,names in os.walk(base,followlinks=False):
        for name in dirs+names:
            p=Path(parent)/name
            if p.is_symlink():raise ValueError('Project contains symlink')
        actual_paths.update((Path(parent)/name).relative_to(base).as_posix() for name in names)
    if actual_paths!=set(files):raise ValueError('Project contains unadmitted files')
    if set(p.name for p in root.iterdir())!={'manifest.json','files'}:raise ValueError('Unexpected project revision content')
    return actual,apis,parameters

def projection(root):
    root=Path(root).resolve();m,apis,parameters=verify(root)
    records={x['path']:tcl(x) for x in m['files']}
    return dict(project_manifest=str(root/'manifest.json'),project_root=str(root/'files'),project_sha256=m['sha256'],entrypoint=m['entrypoint'],entrypoint_sha256=next(x['sha256'] for x in m['files'] if x['path']==m['entrypoint']),source_path=str(root/'files'/m['entrypoint']),admitted_sources=tcl([str(root/'files'/x['path']) for x in m['files']]),project_files=tcl(records),declared_apis=';'.join(apis),source_parameters=tcl({k:tcl(v) for k,v in parameters.items()}))

def registry_record(root, override=None, allow_project_lock=False):
    """Validate only the existing Registry-owned tree, without rewriting it."""
    import configparser
    from script_source_authoring_v1 import record_pointer,validate_record
    root=Path(root)
    if root.is_symlink() or not root.is_dir():raise ValueError('Unsafe Registry record directory')
    ini=root/'script.ini'
    if ini.is_symlink() or not ini.is_file() or ini.stat().st_size>1048576:raise ValueError('Unsafe Registry metadata')
    parser=configparser.ConfigParser(interpolation=None,strict=True)
    parser.read_string(ini.read_text(encoding='utf-8'))
    meta=parser['script'];kind=meta.get('kind','script');language=meta['language']
    if language not in {'Python','Octave'} or kind not in {'script','project'}:raise ValueError('Unsupported Registry source kind/language')
    pointer=record_pointer(root)
    expected={'script.ini'}
    if pointer or override:expected.add('authoring')
    if kind=='project':
        expected.add('project-revisions')
        if allow_project_lock:expected.add('.project-write-lock')
        revisions=root/'project-revisions'
        if revisions.is_symlink() or not revisions.is_dir():raise ValueError('Unsafe Project revisions')
        current=None
        for revision in revisions.iterdir():
            if not re.fullmatch('[a-f0-9]{64}',revision.name):raise ValueError('Unexpected Project revision directory')
            actual,_,_=verify(revision)
            if actual['sha256']!=revision.name:raise ValueError('Project revision directory identity differs')
            if revision.name==meta['project_revision']:current=actual
        if current is None or current['sha256']!=meta['sha256'] or current['entrypoint']!=meta['entrypoint']:raise ValueError('Registry Project source identity differs')
    else:
        name='source.py' if language=='Python' else 'source.m';expected.add(name)
        path=root/name
        if path.is_symlink() or not path.is_file() or path.stat().st_size>4*1024*1024:raise ValueError('Unsafe Registry source')
        if sha(path.read_bytes())!=meta['sha256']:raise ValueError('Registry source SHA differs')
    if {p.name for p in root.iterdir()}!=expected:raise ValueError('Registry record contains unexpected content; preserve and review it')
    for path in root.iterdir():
        if path.is_symlink() or (path.name in {'script.ini','.project-write-lock'} and not path.is_file()):raise ValueError('Unsafe Registry member')
    validate_record(root,override)
    return meta

def registry_rename(source,target,flags):
    """The single Linux transaction primitive used by Registry publication."""
    import ctypes
    libc=ctypes.CDLL(None,use_errno=True);primitive=getattr(libc,'renameat2',None)
    if not sys.platform.startswith('linux') or primitive is None:raise ValueError('Atomic Registry publication requires Linux renameat2; original source is unchanged')
    primitive.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint];primitive.restype=ctypes.c_int
    if primitive(-100,os.fsencode(source),-100,os.fsencode(target),flags):
        error=ctypes.get_errno();raise OSError(error,'Atomic Registry publication refused; original source is unchanged')
    directory_fd=os.open(Path(target).parent,os.O_RDONLY|os.O_DIRECTORY)
    try:os.fsync(directory_fd)
    finally:os.close(directory_fd)

def write(root,language,entrypoint,files):
    root=Path(root);m,_,_=manifest(language,entrypoint,files)
    root.mkdir(parents=True,exist_ok=False)
    try:
        for name,data in files.items():
            p=root/'files'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);p.chmod(0o444)
        (root/'manifest.json').write_text(json.dumps(m,sort_keys=True,indent=2)+'\n')
        verify(root)
    except BaseException:
        shutil.rmtree(root);raise
    return m

class ProjectImportGuard:
    """Pin actual project imports to admitted bytes; not a language sandbox."""
    def __init__(self,root,manifest):
        self.root=Path(root).resolve();self.files={x['path']:x for x in manifest['files']}
        self.modules={PurePosixPath(x).parts[0].removesuffix('.py') for x in self.files}
    def find_spec(self,fullname,path=None,target=None):
        spec=importlib.machinery.PathFinder.find_spec(fullname,path)
        if spec is None:return None
        if spec.origin is None:
            locations=[p for p in spec.submodule_search_locations or [] if Path(p).resolve().is_relative_to(self.root)]
            if locations:spec.submodule_search_locations=locations;return spec
            return None
        origin=Path(spec.origin).resolve()
        if not origin.is_relative_to(self.root):return None
        relative=origin.relative_to(self.root).as_posix()
        if relative not in self.files:raise ImportError(f'Project import is not admitted: {relative}')
        data=safe_read(self.root,relative)
        if sha(data)!=self.files[relative]['sha256']:raise ImportError(f'Project import changed: {relative}')
        class Loader(importlib.abc.Loader):
            def create_module(self,spec):return None
            def exec_module(self,module):exec(compile(data,str(origin),'exec'),module.__dict__)
        spec.loader=Loader();return spec
    def __enter__(self):
        for name in self.modules:
            prior=sys.modules.get(name)
            if prior is not None and not str(getattr(prior,'__file__','')).startswith(str(self.root)+os.sep):raise ImportError(f'Admitted module {name} conflicts with an already-loaded runtime module; rename the project helper')
        sys.meta_path.insert(0,self);return self
    def __exit__(self,*args):
        if self in sys.meta_path:sys.meta_path.remove(self)

def main():
    op=sys.argv[1]
    if op=='provided_inventory':
        from script_api_exports import inventory
        maximum=MAX_BYTES*2+MAX_FILES*2048
        raw=sys.stdin.read(maximum+1)
        if len(raw.encode('utf-8'))>maximum:raise ValueError('Provided API inventory transport exceeds bounds')
        payload=json.loads(raw)
        if not isinstance(payload,dict) or set(payload)!={'language','entrypoint','sources_hex'} or not isinstance(payload['sources_hex'],dict):raise ValueError('Exact source inventory request required')
        sources={name:bytes.fromhex(value) for name,value in payload['sources_hex'].items()}
        print(tcl(inventory(payload['language'],payload['entrypoint'],sources)))
    elif op=='read_external':
        # An explicit host chooser admits only this one ordinary source file.
        # Reuse the maintained identity-stable reader; no source is evaluated.
        if len(sys.argv)!=3:raise ValueError('One chosen source path required')
        from gxtxt_acquisition_project_v1 import ordinary_read
        path=Path(sys.argv[2])
        if not path.is_absolute():raise ValueError('Chosen source requires an absolute path')
        language={'.py':'Python','.m':'Octave'}.get(path.suffix.lower())
        if language is None:raise ValueError('Choose Python or Octave source')
        raw=ordinary_read(path.parent,path.name,4*1024*1024)
        print(tcl(dict(source=raw.decode('utf-8'),sha256=sha(raw),language=language)))
    elif op=='publish_registry':
        # Debian/Linux owner primitive: one filesystem transaction publishes
        # source and schema together while retaining the legacy root layout.
        pending,target=map(Path,sys.argv[2:4]);mode=sys.argv[4]
        from script_source_authoring_v1 import record_pointer
        if mode not in {'new','update','snapshot'}:raise ValueError('Invalid Registry publication mode')
        new_pointer=record_pointer(pending)
        meta=registry_record(pending)
        if mode!='snapshot' and meta.get('kind','script')!='script':raise ValueError('Legacy Registry publication expects a single Script')
        if mode=='update':registry_record(target,new_pointer)
        if pending.parent!=target.parent or pending.parent.is_symlink():raise ValueError('Registry transaction requires the same ordinary parent')
        for path in pending.rglob('*'):
            if path.is_file():
                with path.open('rb') as stream:os.fsync(stream.fileno())
        directory_fd=os.open(pending,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(directory_fd)
        finally:os.close(directory_fd)
        if mode=='snapshot':
            if len(sys.argv)!=13:raise ValueError('Complete Registry snapshot commit pins required')
            source=Path(sys.argv[5]);source_record,source_sha=sys.argv[6:8]
            for parent,device,inode in [(source.parent,sys.argv[8],sys.argv[9]),(target.parent,sys.argv[10],sys.argv[11])]:
                if parent.is_symlink() or (parent.stat().st_dev,parent.stat().st_ino)!=(int(device),int(inode)):raise ValueError('Registry owner changed before snapshot commit')
            original=registry_record(source,allow_project_lock=sys.argv[12]=='1')
            if sha((source/'script.ini').read_bytes())!=source_record or original['sha256']!=source_sha or meta['sha256']!=source_sha:raise ValueError('Registry source/record changed before snapshot commit')
        registry_rename(pending,target,2 if mode=='update' else 1)
        if mode=='update':shutil.rmtree(pending)
    elif op=='stage_registry':
        pending,target=map(Path,sys.argv[2:4])
        if pending.parent!=target.parent or pending.parent.is_symlink() or not re.fullmatch(r'\.'+re.escape(target.name)+r'\.snapshot-[0-9-]+\.pending',pending.name):raise ValueError('Invalid Registry snapshot staging path')
        pending.mkdir(mode=0o700,exist_ok=False)
    elif op=='remove_registry':
        root=Path(sys.argv[2]);record_sha,source_sha=sys.argv[3:5]
        parent_identity=(int(sys.argv[5]),int(sys.argv[6]));allow_lock=sys.argv[7]=='1'
        if root.parent.is_symlink() or (root.parent.stat().st_dev,root.parent.stat().st_ino)!=parent_identity:raise ValueError('Registry owner changed before removal')
        meta=registry_record(root,allow_project_lock=allow_lock)
        if sha((root/'script.ini').read_bytes())!=record_sha or meta['sha256']!=source_sha:raise ValueError('Registry record changed before removal')
        quarantine=root.with_name('.'+root.name+'.removed-'+uuid.uuid4().hex)
        registry_rename(root,quarantine,1)
        # This exact validated record is no longer a visible Registry identity.
        # Never remove a later record that might appear under the old name.
        shutil.rmtree(quarantine)
    elif op=='authoring':
        from script_source_authoring_v1 import dispatch
        raw=sys.stdin.read(8388609)
        if len(raw.encode('utf-8'))>8388608:raise ValueError('Source authoring request exceeds8MiB')
        print(tcl(dispatch(Path(sys.argv[2]),json.loads(raw))))
    elif op=='write':
        root,language,entrypoint=sys.argv[2:5]
        maximum=MAX_BYTES*2+MAX_FILES*2048
        raw=sys.stdin.read(maximum+1)
        if len(raw)>maximum:raise ValueError('Project source transport exceeds bounds')
        payload=json.loads(raw)
        write(root,language,entrypoint,{k:bytes.fromhex(v) for k,v in payload.items()})
        print(tcl(projection(root)))
    elif op=='verify':print(tcl(projection(sys.argv[2])))
    elif op=='read':
        root=Path(sys.argv[2]);m,_,_=verify(root)
        if m['sha256']!=sys.argv[3]:raise ValueError('Project source revision changed')
        values={}
        for item in m['files']:
            data=safe_read(root/'files',item['path'])
            if sha(data)!=item['sha256']:raise ValueError('Project changed while reading sources')
            values[item['path']]=data.decode('utf-8')
        print(tcl(values))
    elif op=='copy':
        root,dest=map(Path,sys.argv[2:4]);m,_,_=verify(root)
        if dest.exists():raise ValueError('Snapshot destination exists')
        write(dest,m['language'],m['entrypoint'],{x['path']:safe_read(root/'files',x['path']) for x in m['files']})
        print(tcl(projection(dest)))
    elif op=='export':
        root,dest=map(Path,sys.argv[2:4]);m,_,_=verify(root)
        raw=sys.stdin.read(1048577)
        if len(raw.encode())>1048576:raise ValueError('Portable metadata exceeds bounds')
        import tkinter
        parts=tkinter.Tcl().splitlist(raw)
        if len(parts)%2:raise ValueError('Invalid portable Registry metadata')
        metadata={k:v for k,v in zip(parts[::2],parts[1::2]) if k in PORTABLE_FIELDS and (k!='source_authoring_v1' or v)}
        from script_source_authoring_v1 import portable
        authoring=portable(root.parent.parent,metadata.get('source_authoring_v1','')) if metadata.get('source_authoring_v1') else {}
        package=dict(schema='gxtxt.script_project_package.v2' if authoring else 'gxtxt.script_project_package.v1',project_sha256=m['sha256'],metadata=metadata,metadata_sha256=sha(json.dumps(metadata,sort_keys=True,separators=(',',':')).encode()))
        with zipfile.ZipFile(dest,'x',compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('manifest.json',(root/'manifest.json').read_bytes())
            z.writestr('registry.json',json.dumps(package,sort_keys=True,indent=2)+'\n')
            for item in m['files']:z.writestr('files/'+item['path'],safe_read(root/'files',item['path']))
            for name,content in authoring.items():
                info=zipfile.ZipInfo('authoring/'+name);info.external_attr=(0o100000|0o444)<<16
                z.writestr(info,content)
    elif op=='import':
        src,dest=map(Path,sys.argv[2:4])
        if src.is_symlink() or not src.is_file():raise ValueError('Project import requires a regular archive')
        with zipfile.ZipFile(src) as z:
            entries=z.infolist()
            if len(entries)>MAX_FILES+515 or sum(x.file_size for x in entries)>MAX_BYTES+18*1048576:raise ValueError('Project archive exceeds bounds')
            if len(set(x.filename for x in entries))!=len(entries) or any(x.flag_bits&1 or (x.external_attr>>16)&0o170000==0o120000 for x in entries):raise ValueError('Unsafe ZIP entries')
            m=json.loads(z.read('manifest.json'))
            if m.get('schema')!=SCHEMA or not isinstance(m.get('files'),list) or not 1<=len(m['files'])<=MAX_FILES:raise ValueError('Unsupported/bounded project archive manifest required')
            expected={'manifest.json'}|{'files/'+relative(x['path'],m['language']) for x in m['files']}
            metadata={}
            if 'registry.json' in z.namelist():
                expected.add('registry.json')
                package=json.loads(z.read('registry.json'))
                metadata=package.get('metadata')
                if package.get('schema') not in {'gxtxt.script_project_package.v1','gxtxt.script_project_package.v2'} or package.get('project_sha256')!=m['sha256'] or not isinstance(metadata,dict) or set(metadata)-PORTABLE_FIELDS or not all(isinstance(k,str) and isinstance(v,str) for k,v in metadata.items()) or package.get('metadata_sha256')!=sha(json.dumps(metadata,sort_keys=True,separators=(',',':')).encode()):raise ValueError('Portable Registry metadata integrity differs')
            authoring={}
            if metadata.get('source_authoring_v1'):
                from script_source_authoring_v1 import decode_pointer
                import source_authoring_v1 as owner
                authoring={x.filename[len('authoring/'):]:z.read(x) for x in entries if x.filename.startswith('authoring/')}
                for item in entries:
                    if item.filename.startswith('authoring/') and (item.external_attr>>16)!=0o100000|owner.FILE_MODE:raise ValueError('Authoring package regular file mode differs')
                owner._validated_payload(authoring,decode_pointer(metadata['source_authoring_v1']))
                expected.update('authoring/'+name for name in authoring)
            if {x.filename for x in entries}!=expected:raise ValueError('Archive has unadmitted content')
            files={x['path']:z.read('files/'+x['path']) for x in m['files']}
            actual,_,_=manifest(m['language'],m['entrypoint'],files)
            if m!=actual:raise ValueError('Archive manifest digest differs')
            write(dest,m['language'],m['entrypoint'],files)
            authoring_root=None
            if authoring:
                import source_authoring_v1 as owner
                authoring_root=Path(str(dest)+'.authoring');authoring_root.mkdir(mode=0o700)
                owner._store(authoring_root,authoring)
        result=projection(dest);result['portable_metadata']=tcl(metadata)
        if authoring_root:result['portable_authoring_root']=str(authoring_root)
        print(tcl(result))
    else:raise ValueError('Unknown project operation')
if __name__=='__main__':main()
