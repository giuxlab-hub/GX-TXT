"""Observational local runtime inventory and inert AST import analysis/editing."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse,ast,base64,datetime,hashlib,importlib.machinery,importlib.metadata,json,os,pkgutil,sys,tokenize,io
from pathlib import Path

def quote(value):
    value=str(value)
    if not value:return '{}'
    table={'\\':'\\\\',' ':'\\ ','\n':'\\n','\r':'\\r','\t':'\\t','{':'\\{','}':'\\}','[':'\\[',']':'\\]','$':'\\$',';':'\\;','"':'\\"'}
    return ''.join(table.get(c,c) for c in value)
def tcl(value):
    if isinstance(value,dict):return ' '.join(quote(k)+' '+quote(tcl(v)) for k,v in value.items())
    if isinstance(value,(list,tuple)):return ' '.join(quote(tcl(v)) for v in value)
    if value is None:return ''
    if isinstance(value,bool):return '1' if value else '0'
    return str(value)
def identity():
    return dict(executable=str(Path(sys.executable).resolve()),version=sys.version.split()[0],prefix=sys.prefix,base_prefix=sys.base_prefix,virtual_environment=sys.prefix!=sys.base_prefix,search_paths=[str(Path(p or os.getcwd()).resolve()) for p in sys.path],scanned_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
def resolve(module,paths=None):
    """Walk specs without importing any parent package or executing its loader."""
    if not module or module.startswith('.'):return dict(status='UNKNOWN',origin='',reason='Relative import requires a package context')
    paths=list(sys.path if paths is None else paths);spec=None
    try:
        parts=module.split('.')
        for index in range(len(parts)):
            name='.'.join(parts[:index+1])
            if index==0 and name in sys.builtin_module_names:
                spec=importlib.machinery.BuiltinImporter.find_spec(name)
            else:
                spec=importlib.machinery.FrozenImporter.find_spec(name) if index==0 else None
                if spec is None:spec=importlib.machinery.PathFinder.find_spec(name,paths)
            if spec is None:return dict(status='MISSING',origin='',reason='No static module spec in the effective execution search path')
            if index<len(parts)-1:
                if spec.submodule_search_locations is None:return dict(status='MISSING',origin=str(spec.origin or ''),reason='Parent is not a package')
                paths=list(spec.submodule_search_locations)
        return dict(status='AVAILABLE',origin=str(spec.origin or 'namespace package'),locations=list(spec.submodule_search_locations or []),reason='Static module spec; module initialization and binary loading are not tested')
    except KeyError:
        # PathFinder's nested namespace path consults sys.modules[parent]. A
        # nonexecuting audit intentionally never initializes that parent.
        return dict(status='UNKNOWN',origin='',reason='Nested namespace package needs an initialized parent; no package was loaded for this static audit')
    except (OSError,ValueError,ImportError,AttributeError) as exc:return dict(status='UNKNOWN',origin='',reason=f'{type(exc).__name__}: {exc}')
def distribution_map():
    try:return importlib.metadata.packages_distributions()
    except (OSError,ValueError):return {}
def inventory(limit=1500,offset=0):
    mapping=distribution_map();names=set(sys.builtin_module_names)|set(getattr(sys,'stdlib_module_names',()))|set(mapping)
    for entry in pkgutil.iter_modules():names.add(entry.name)
    rows=[]
    for name in sorted(names)[offset:offset+limit]:
        item=resolve(name);dist=mapping.get(name,[]);versions={}
        for distribution in dist:
            try:versions[distribution]=importlib.metadata.version(distribution)
            except importlib.metadata.PackageNotFoundError:versions[distribution]='metadata unavailable'
        item.update(module=name,classification='builtin' if name in sys.builtin_module_names else 'stdlib' if name in getattr(sys,'stdlib_module_names',()) else 'third_party_or_local',distributions=versions)
        rows.append(item)
    return dict(identity=identity(),total=len(names),offset=offset,limit=limit,entries=rows,qualification='No discovered package was imported; import names and distribution names remain distinct')
def analyze(source,paths=None):
    digest=hashlib.sha256(source.encode('utf-8')).hexdigest()
    try:tree=ast.parse(source.removeprefix('\ufeff'))
    except SyntaxError as e:return dict(identity=identity(),source_sha256=digest,status='ERROR',issues=[dict(status='ERROR',module='',line=e.lineno or 0,column=e.offset or 0,reason=e.msg)],imports=[])
    imports=[]
    class Visitor(ast.NodeVisitor):
        def __init__(self):self.context='mandatory'
        def scope(self,nodes,context):
            old=self.context;self.context=context
            for node in nodes:self.visit(node)
            self.context=old
        def visit_Import(self,node):
            for alias in node.names:self.entry(node,alias.name,alias.asname or '',False)
        def visit_ImportFrom(self,node):self.entry(node,'.'*node.level+(node.module or ''),','.join(alias.name for alias in node.names),True)
        def entry(self,node,module,alias,from_import):
            result=resolve(module,paths);raw=result['status']
            if self.context!='mandatory' and raw=='MISSING':result['status']='OPTIONAL' if self.context=='optional' else 'UNKNOWN'
            result.update(module=module,alias_or_members=alias,from_import=from_import,line=node.lineno,column=node.col_offset,intent=self.context,static_status=raw);imports.append(result)
        def visit_Try(self,node):
            optional=any(h.type is None or any(isinstance(n,ast.Name) and n.id in {'ImportError','ModuleNotFoundError'} for n in ast.walk(h.type)) for h in node.handlers)
            self.scope(node.body,'optional' if optional else self.context)
            for h in node.handlers:self.scope(h.body,'conditional')
            self.scope(node.orelse,'conditional');self.scope(node.finalbody,self.context)
        def visit_If(self,node):self.scope(node.body,'conditional');self.scope(node.orelse,'conditional')
        def visit_FunctionDef(self,node):self.scope(node.body,'conditional')
        visit_AsyncFunctionDef=visit_FunctionDef
        def visit_Call(self,node):
            dynamic=isinstance(node.func,ast.Name) and node.func.id=='__import__' or isinstance(node.func,ast.Attribute) and node.func.attr=='import_module'
            if dynamic:imports.append(dict(module=ast.unparse(node.func),status='UNKNOWN',line=node.lineno,column=node.col_offset,intent='dynamic',origin='',reason='Dynamic imports cannot be resolved without executing source'))
            self.generic_visit(node)
    Visitor().visit(tree)
    missing=[x for x in imports if x['status']=='MISSING'];status='MISSING' if missing else 'WARNING' if any(x['status'] in {'UNKNOWN','OPTIONAL'} for x in imports) else 'AVAILABLE'
    return dict(identity=identity(),source_sha256=digest,status=status,imports=imports,issues=missing,qualification='Static inference only. Imported attributes and runtime side effects are not evaluated')
def audit_imports(admission):
    """Extend the SAME analyze/resolve owner over host-admitted exact sources."""
    if not isinstance(admission,dict) or admission.get('schema')!='gxtxt.python_import_audit_request.v1' or admission.get('scope') not in {'script','project','framework'}:
        raise ValueError('Invalid admitted Python audit scope')
    sources=admission.get('sources')
    if not isinstance(sources,list) or not sources or len(sources)>1000:
        raise ValueError('Audit requires 1..1000 admitted Python source files')
    mapping=distribution_map();versions={};imports=[];files=[];total=0;seen=set();errors=[]
    framework=Path(__file__).resolve().parents[2]
    client=framework/'core'/'python'
    for item in sources:
        if not isinstance(item,dict) or not {'path','root','sha256','logical_id'}<=item.keys():
            raise ValueError('An admitted source requires exact path/root/SHA/logical identity')
        original=Path(item['path']);root=Path(item['root']).resolve(strict=True);path=original.resolve(strict=True)
        if not path.is_relative_to(root) or path.suffix!='.py' or path in seen:
            raise ValueError('Audit source is outside its admitted root or duplicated')
        probe=root
        for part in original.absolute().relative_to(root).parts:
            probe/=part
            if probe.is_symlink():raise ValueError('Audit sources cannot contain symlinks')
        if not path.is_file() or path.stat().st_size>4194304:
            raise ValueError('Admitted Python source exceeds its 4 MiB bound')
        raw=path.read_bytes();total+=len(raw)
        if total>33554432:raise ValueError('Audit source scope exceeds the 32 MiB bound')
        sha=hashlib.sha256(raw).hexdigest()
        if sha!=item['sha256']:raise ValueError('Admitted Python source changed before audit')
        encoding,_=tokenize.detect_encoding(io.BytesIO(raw).readline)
        source=raw.decode('utf-8' if encoding=='utf-8-sig' else encoding)
        # Execution admits the project root, not whichever helper tab happens
        # to be active. The framework client is an actual existing runtime path.
        local_paths=[str(root),str(path.parent)] if admission['scope']=='framework' else [str(root)]
        paths=list(dict.fromkeys(local_paths+[str(client)]+[p for p in sys.path if p and Path(p).resolve()!=path.parent]))
        report=analyze(source,paths)
        relative=path.relative_to(root).as_posix()
        files.append(dict(logical_id=item['logical_id'],path=str(path),root=str(root),relative_file=relative,sha256=sha,size_bytes=len(raw),status=report['status'],effective_search_paths=paths))
        seen.add(path)
        if report['status']=='ERROR':
            for issue in report['issues']:
                row=dict(issue,source_file=str(path),logical_id=item['logical_id'],classification='unknown',distributions={},intent='invalid_source',static_status='ERROR')
                imports.append(row);errors.append(row)
        for found in report['imports']:
            row=dict(found,source_file=str(path),logical_id=item['logical_id'],relative_file=relative)
            module=row['module'];resolved_module=module
            if module.startswith('.'):
                level=len(module)-len(module.lstrip('.'));package=path.relative_to(root).parts[:-1]
                if package and (path.parent/'__init__.py').is_file() and level<=len(package):
                    resolved_module='.'.join((*package[:len(package)-level+1],module.lstrip('.'))).strip('.')
                    resolution=resolve(resolved_module,paths)
                    row.update(resolution,static_status=resolution['status'],resolved_module=resolved_module)
                    if resolution['status']=='AVAILABLE':row['reason']='Relative project package resolved statically; no code executed'
            top=resolved_module.split('.')[0]
            origin=row.get('origin','')
            is_local=False
            if origin and origin not in {'built-in','frozen','namespace package'}:
                try:is_local=Path(origin).resolve().is_relative_to(root) or Path(origin).resolve().is_relative_to(client)
                except (OSError,ValueError):pass
            installed_origin=False
            if origin and origin not in {'built-in','frozen','namespace package'}:
                installed_origin=any(Path(origin).resolve().is_relative_to(Path(p).resolve()) for p in sys.path if p and Path(p).name in {'site-packages','dist-packages'})
            row['classification']='local' if is_local else 'builtin' if top in sys.builtin_module_names else 'stdlib' if top in getattr(sys,'stdlib_module_names',()) else 'third_party' if mapping.get(top) or installed_origin else 'unknown'
            owners={}
            for distribution in mapping.get(top,[]):
                if distribution not in versions:
                    try:versions[distribution]=importlib.metadata.version(distribution)
                    except importlib.metadata.PackageNotFoundError:versions[distribution]='metadata unavailable'
                owners[distribution]=versions[distribution]
            row['distributions']=owners
            if row.get('intent')=='optional':row['status']='OPTIONAL'
            elif row.get('intent') in {'conditional','dynamic'}:row['status']='UNKNOWN'
            if found.get('from_import'):row['reason']=row.get('reason','')+'; imported members may be attributes, not separate distributions'
            imports.append(row)
        if hashlib.sha256(path.read_bytes()).hexdigest()!=sha:raise ValueError('Admitted Python source changed during audit')
        if len(imports)>20000:raise ValueError('Python import audit exceeds its 20000-result bound; choose a smaller scope')
    summary={status:sum(row['status']==status for row in imports) for status in ('AVAILABLE','MISSING','OPTIONAL','UNKNOWN','ERROR')}
    return dict(schema='gxtxt.python_import_audit.v1',identity=identity(),scope=admission['scope'],scope_identity=admission.get('scope_identity',''),file_count=len(files),source_bytes=total,sources=files,imports=imports,issues=[row for row in imports if row['status'] in {'MISSING','ERROR'}],summary=summary,status='ERROR' if errors else 'MISSING' if summary['MISSING'] else 'WARNING' if summary['OPTIONAL']+summary['UNKNOWN'] else 'AVAILABLE',complete=not admission.get('truncated',False) and not errors,truncated=bool(admission.get('truncated',False)),qualification='Static availability only; source and dependencies are not executed, and no packages are installed')
def organize(source,statements):
    marker='\ufeff' if source.startswith('\ufeff') else ''
    body=source.removeprefix('\ufeff')
    tree=ast.parse(body);before=hashlib.sha256(source.encode()).hexdigest();newline='\r\n' if '\r\n' in source else '\n'
    existing={ast.dump(n,include_attributes=False) for n in ast.walk(tree) if isinstance(n,(ast.Import,ast.ImportFrom))}
    names={}
    for n in tree.body:
        if isinstance(n,(ast.Import,ast.ImportFrom)):
            for a in n.names:names[a.asname or a.name.split('.')[0]]=ast.dump(n,include_attributes=False)
    ordinary=[];future=[];duplicates=[]
    for statement in statements:
        parsed=ast.parse(statement)
        if len(parsed.body)!=1 or not isinstance(parsed.body[0],(ast.Import,ast.ImportFrom)):raise ValueError('Choose one explicit import statement per row')
        n=parsed.body[0]
        if any(a.name=='*' for a in n.names):raise ValueError('Wildcard imports are not supported by the organizer')
        signature=ast.dump(n,include_attributes=False)
        if signature in existing:duplicates.append(statement);continue
        for a in n.names:
            bound=a.asname or a.name.split('.')[0]
            if bound in names and names[bound]!=signature:raise ValueError(f'Import alias conflict: {bound}')
            names[bound]=signature
        existing.add(signature)
        (future if isinstance(n,ast.ImportFrom) and n.module=='__future__' else ordinary).append(statement.strip())
    lines=body.splitlines(keepends=True);doc_end=0
    if tree.body and isinstance(tree.body[0],ast.Expr) and isinstance(tree.body[0].value,ast.Constant) and isinstance(tree.body[0].value.value,str):doc_end=tree.body[0].end_lineno
    header=doc_end
    if not doc_end:
        for i,line in enumerate(lines):
            if line.strip()=='' or line.lstrip().startswith('#'):header=i+1
            else:break
    future_end=header
    for node in tree.body:
        if isinstance(node,ast.ImportFrom) and node.module=='__future__':future_end=max(future_end,node.end_lineno)
    ordinary_end=future_end
    for node in tree.body:
        if isinstance(node,(ast.Import,ast.ImportFrom)):ordinary_end=max(ordinary_end,node.end_lineno)
        elif getattr(node,'lineno',0)>future_end:break
    insertions={}
    if future:insertions.setdefault(future_end,[]).extend(future)
    if ordinary:insertions.setdefault(ordinary_end,[]).extend(ordinary)
    for index,items in sorted(insertions.items(),reverse=True):
        prefix=newline if index and not lines[index-1].endswith(('\n','\r')) else ''
        lines[index:index]=[prefix+newline.join(items)+newline]
    result=marker+''.join(lines);ast.parse(result.removeprefix('\ufeff'))
    return dict(source=result,before_sha256=before,after_sha256=hashlib.sha256(result.encode()).hexdigest(),statements=statements,duplicates=duplicates,changed=result!=source)
def main():
    a=argparse.ArgumentParser();a.add_argument('operation',choices=['inventory','preflight','organize','audit']);a.add_argument('--source');a.add_argument('--statement',action='append',default=[]);a.add_argument('--offset',type=int,default=0);a.add_argument('--limit',type=int,default=1500);a.add_argument('--report');args=a.parse_args()
    try:
        if args.operation=='inventory':result=inventory(max(1,min(args.limit,2000)),max(0,args.offset))
        elif args.operation=='audit':
            request=sys.stdin.buffer.read(2097153)
            if len(request)>2097152:raise ValueError('Audit admission request exceeds 2 MiB')
            result=audit_imports(json.loads(request))
        else:
            raw=Path(args.source).read_bytes() if args.source else sys.stdin.buffer.read(4194305)
            if len(raw)>4194304:raise ValueError('Python source limit is 4 MiB')
            encoding,_=tokenize.detect_encoding(io.BytesIO(raw).readline);source=raw.decode('utf-8' if encoding=='utf-8-sig' else encoding)
            result=analyze(source) if args.operation=='preflight' else organize(source,args.statement)
            result['original_bytes_sha256']=hashlib.sha256(raw).hexdigest()
        if args.report:
            with open(args.report,'x',encoding='utf-8') as out:json.dump(result,out,ensure_ascii=False,indent=2)
        print(tcl(dict(ok=1,result=result)))
    except Exception as e:print(tcl(dict(ok=0,error=f'{type(e).__name__}: {e}')))
if __name__=='__main__':main()
