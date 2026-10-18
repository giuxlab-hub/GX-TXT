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
    a=argparse.ArgumentParser();a.add_argument('operation',choices=['inventory','preflight','organize']);a.add_argument('--source');a.add_argument('--statement',action='append',default=[]);a.add_argument('--offset',type=int,default=0);a.add_argument('--limit',type=int,default=1500);a.add_argument('--report');args=a.parse_args()
    try:
        if args.operation=='inventory':result=inventory(max(1,min(args.limit,2000)),max(0,args.offset))
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
