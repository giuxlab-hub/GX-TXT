#!/usr/bin/env python3
# GX-TXT Session HTML Export
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse, base64, csv, hashlib, html, json, os, re, shutil, subprocess, sys, time, zipfile
from pathlib import Path, PurePosixPath
from collections import defaultdict

TEXT_EXT={'.txt','.log','.ini','.json','.yaml','.yml','.cfg','.dat','.asc','.cir','.net','.lib','.tsv'}
GRAPH_EXT={'.png','.jpg','.jpeg','.webp','.svg'}
MD_EXT={'.md','.markdown'}
CSV_EXT={'.csv'}
CHUNK_ROWS=2000
MAX_INLINE_CSV_BYTES=64*1024*1024
MAX_LARGE_CSV_PREVIEW_ROWS=10000
NAV_LINKS=[('overview','Overview','index.html'),('datasets','Datasets','datasets/index.html'),('analyses','Analyses','analyses/index.html'),('scripts','Session scripts','scripts/index.html'),('graphs','Graphs','graphs/index.html'),('documents','Documentation / Notes','documents/index.html'),('files','Files / Artifacts','files/index.html'),('provenance','Metadata / Provenance','provenance/index.html'),('export','Export information','export-info.html')]
ACTIVE_NAV={k for k,_,_ in NAV_LINKS}


def h(s): return html.escape(str(s or ''), quote=True)
def b64decode(s): return base64.b64decode(s).decode('utf-8')
def sha_text(s): return hashlib.sha256(s.encode('utf-8')).hexdigest()[:12]
def safe_name(name):
    x=re.sub(r'[^A-Za-z0-9._-]+','_',name).strip('._')
    return x[:80] or 'item'
def safe_rel(text):
    p=PurePosixPath(text)
    if not text or text.startswith('/') or re.match(r'^[A-Za-z]:[/\\]',text) or any(x in ('','.','..') for x in p.parts):
        raise ValueError(f'unsafe Session path in inspection snapshot: {text}')
    return p

def file_sha(path):
    hh=hashlib.sha256()
    with path.open('rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''): hh.update(c)
    return hh.hexdigest()

def now(): return time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())


def parse_snapshot(path:Path):
    lines=path.read_text(encoding='utf-8').splitlines()
    if not lines or lines[0].strip()!='GXTXT_SESSION_INSPECTION_V1': raise ValueError('invalid Session Inspection snapshot')
    rec=defaultdict(lambda: defaultdict(dict))
    for line in lines[1:]:
        if not line: continue
        parts=line.split('\t')
        if len(parts)!=5 or parts[0]!='REC': raise ValueError('malformed Session Inspection snapshot record')
        cat=parts[1]; obj=b64decode(parts[2]); field=b64decode(parts[3]); val=b64decode(parts[4])
        rec[cat][obj][field]=val
    return rec


def nav(prefix=''):
    return '<nav>'+''.join(f'<a href="{prefix}{u}">{h(t)}</a>' for k,t,u in NAV_LINKS if k in ACTIVE_NAV)+'</nav>'

def shell(title, body, prefix=''):
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{h(title)}</title><link rel="stylesheet" href="{prefix}assets/app.css"></head><body><header><a href="{prefix}index.html">GX-TXT Session HTML Export</a></header><div class="layout">{nav(prefix)}<main><h1>{h(title)}</h1>{body}</main></div></body></html>'''

def kv_table(d):
    if not d:return '<p class="muted">No information available.</p>'
    return '<div class="kv">'+''.join(f'<div><strong>{h(k)}</strong></div><div>{h(v)}</div>' for k,v in d.items() if str(v)!='')+'</div>'

def write(path:Path,text:str):
    path.parent.mkdir(parents=True,exist_ok=True); path.write_text(text,encoding='utf-8',newline='\n')


def detect_delimiter(ds):
    v=(ds.get('canonical_delimiter') or ds.get('delimiter') or 'comma').lower()
    return {'comma':',','semicolon':';','tab':'\t',',':',',';':';','\t':'\t'}.get(v,',')

def dataset_variables(ds):
    out=[]
    n=1
    while f'var{n}_variable_id' in ds or f'var{n}_canonical' in ds:
        item={}
        for key,val in ds.items():
            p=f'var{n}_'
            if key.startswith(p):item[key[len(p):]]=val
        out.append(item); n+=1
    return out


def copy_inventory(session:Path,out:Path,files_rec):
    mapping={}; entries=[]
    for rel,meta in sorted(files_rec.items()):
        p=safe_rel(rel); src=(session/Path(p.as_posix())).resolve()
        root=session.resolve()
        if root!=src and root not in src.parents:
            # Snapshot should never expose an out-of-Session path.
            continue
        if not src.is_file(): continue
        if meta.get('sha256') and file_sha(src)!=meta['sha256']: raise ValueError(f'Session file changed during HTML export: {rel}')
        key='f_'+sha_text(rel)
        ext=src.suffix.lower(); dstrel=PurePosixPath('files','content',key+ext)
        dst=out/Path(dstrel.as_posix()); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
        mapping[rel]=dstrel.as_posix()
        entries.append({'rel':rel,'size':src.stat().st_size,'sha256':meta.get('sha256') or file_sha(src),'ext':ext,'copied':dstrel.as_posix()})
    return mapping,entries


def make_csv(dataset_id, ds, src:Path, out:Path, original_link:str):
    key='ds_'+sha_text(dataset_id)
    ddir=out/'data'/key; ddir.mkdir(parents=True,exist_ok=True)
    delim=detect_delimiter(ds); chunks=[]; headers=[]; rowcount=0; chunk=[]
    def flush(rows,idx):
        fn=f'chunk_{idx:05d}.js'; p=ddir/fn
        p.write_text('window.GXCSV&&GXCSV.register('+str(idx)+','+json.dumps(rows,ensure_ascii=False,separators=(',',':'))+');\n',encoding='utf-8')
        chunks.append('../data/'+key+'/'+fn)
    large=src.stat().st_size>MAX_INLINE_CSV_BYTES
    with src.open('r',encoding='utf-8-sig',newline='') as fh:
        rd=csv.reader(fh,delimiter=delim)
        try: headers=next(rd)
        except StopIteration: headers=[]
        idx=0
        for row in rd:
            chunk.append(row); rowcount+=1
            if len(chunk)>=CHUNK_ROWS:
                flush(chunk,idx); idx+=1; chunk=[]
            if large and rowcount>=MAX_LARGE_CSV_PREVIEW_ROWS:
                break
        if chunk or not chunks: flush(chunk,idx)
    meta={'headers':headers,'rowCount':rowcount,'chunkRows':CHUNK_ROWS,'chunkCount':len(chunks),'chunkFiles':chunks}
    vars_=dataset_variables(ds)
    varrows=''.join('<tr>'+''.join(f'<td>{h(v.get(k,""))}</td>' for k in ('variable_id','display_label','canonical','unit','semantic_role','value_kind'))+'</tr>' for v in vars_)
    schema=f'<table><thead><tr><th>Variable ID</th><th>Display label</th><th>Canonical name</th><th>Unit</th><th>Semantic role</th><th>Value kind</th></tr></thead><tbody>{varrows}</tbody></table>' if vars_ else '<p class="muted">No Variable Schema entries available.</p>'
    note=''
    if large:
        total=ds.get('row_count','')
        total_text=f' of {h(total)} registered rows' if total else ''
        note=f'<p class="viewer-note">Showing the first {rowcount:,} rows{total_text} for responsive offline browsing. Sorting and filtering apply to the currently loaded chunk. The complete original CSV remains available unchanged through the download link.</p>'
    elif rowcount>CHUNK_ROWS:
        note='<p class="viewer-note">Data are loaded in local chunks. Sorting and filtering apply to the currently loaded chunk; all scientific rows remain present in the export and the original CSV is available unchanged.</p>'
    page=f'''<div class="card"><h2>Dataset</h2>{kv_table({k:ds.get(k,'') for k in ['id','kind','contract','format','source_module','source','sha256','canonical_sha256','created_at']})}</div><div class="card"><h2>Variable Schema</h2>{schema}</div><div class="card"><h2>CSV data</h2>{note}<div class="controls"><label>Filter <input id="csv-filter" placeholder="text or numeric condition, e.g. >5"></label><button id="csv-prev">Previous</button><button id="csv-next">Next</button><a href="../{h(original_link)}" download>Open/download original CSV</a><span id="csv-status" class="muted"></span></div><div class="table-wrap"><table><thead id="csv-head"></thead><tbody id="csv-body"></tbody></table></div></div><script src="../assets/csv-viewer.js"></script><script>GXCSV.init({json.dumps(meta,ensure_ascii=False).replace('<','\\u003c').replace('>','\\u003e').replace('&','\\u0026')});</script>'''
    return page,rowcount,len(headers)


def markdown_page(title,source,original_link):
    b64=base64.b64encode(source.encode('utf-8')).decode('ascii')
    return f'''<div class="card"><div class="controls"><a href="../{h(original_link)}" download>Open/download source</a><span class="readonly">Read-only rendering</span></div><div id="md" class="markdown"></div></div><script src="../assets/markdown-viewer.js"></script><script>GXMarkdown.renderBase64("{b64}","#md");</script>'''

def graph_page(title,img_link,original_link,is_svg=False,clean_link=None,note_text=None):
    original_action=(f'<a href="../{h(original_link)}" download>Download original SVG</a>' if is_svg else f'<a href="../{h(original_link)}" target="_blank" rel="noopener">Open original resolution</a>')
    annotation_control=(f'<label><input id="show-annotations" type="checkbox" checked> Show annotations</label>' if clean_link else '')
    clean_attr=f' data-clean="../{h(clean_link)}"' if clean_link else ''
    note=''
    if note_text is not None:
        encoded=base64.b64encode(note_text.encode('utf-8')).decode('ascii')
        note=f'<div class="card"><h2>Graph Notes</h2><div id="graph-note" class="markdown"></div></div><script src="../assets/markdown-viewer.js"></script><script>GXMarkdown.renderBase64("{encoded}","#graph-note");</script>'
    return f'''<div class="controls"><button id="zoom-in">Zoom in</button><button id="zoom-out">Zoom out</button><button id="reset">Fit/reset</button>{annotation_control}{original_action}</div><div id="stage" class="graph-stage"><img id="graph" src="../{h(img_link)}"{clean_attr} alt="{h(title)}"></div><script src="../assets/graph-viewer.js"></script><script>GXGraph.init(document.querySelector('#stage'),document.querySelector('#graph'));</script>{note}'''

def graph_note_associations(session:Path):
    manifest=session/'metadata'/'manifest.ini'
    if not manifest.is_file(): return {}
    sections={};current=''
    for raw in manifest.read_text(encoding='utf-8').splitlines():
        line=raw.strip()
        if line.startswith('[') and line.endswith(']'):
            current=line[1:-1];sections.setdefault(current,{})
        elif current and '=' in raw and not line.startswith((';','#')):
            key,val=raw.split('=',1);sections[current][key.strip()]=val.strip()
    refs={}
    for name,fields in sections.items():
        if not re.fullmatch(r'graph_notes\.[0-9]+',name):continue
        identity=(fields.get('kind',''),fields.get('module_id',''),fields.get('graph_id',''),fields.get('variant_id',''),fields.get('clone_id',''))
        rel=fields.get('file','')
        if rel:
            try: safe_rel(rel)
            except ValueError: continue
            refs[identity]=rel
    base_keys={}
    graph_map=session/'analysis'/'.plot_graph_map.tsv'
    if graph_map.is_file():
        for line in graph_map.read_text(encoding='utf-8').splitlines()[1:]:
            parts=line.split('\t')
            if len(parts)<2:continue
            try: rel=Path(parts[0]).resolve().relative_to(session.resolve()).as_posix()
            except ValueError:continue
            base_keys[rel]=parts[1]
    out={}
    for identity,rel in refs.items():
        kind,mid,gid,vid,clone=identity
        if kind=='clone':
            out[f'analysis/core.plot_clones/{clone}/graph.png']=rel
        elif kind=='provider' and vid:
            prefix=f'analysis/{mid}/variants/{gid}/{vid}/'
            out[prefix]=rel
        elif kind=='provider':
            for graph_rel,key in base_keys.items():
                if key==gid and graph_rel.startswith(f'analysis/{mid}/'):
                    out[graph_rel]=rel
    return out


def export_site(session:Path,snapshot:Path,out:Path,module_version:str,framework_version:str,make_zip:bool,annotation_renderer:Path|None=None):
    session=session.resolve(); out=out.resolve()
    if out.exists(): raise ValueError(f'output already exists: {out}')
    zip_target=out.parent/(out.name+'.zip')
    if make_zip and zip_target.exists(): raise ValueError(f'ZIP output already exists: {zip_target}')
    rec=parse_snapshot(snapshot)
    out.mkdir(parents=True)
    assets_src=Path(__file__).with_name('assets'); shutil.copytree(assets_src,out/'assets')
    mapping,file_entries=copy_inventory(session,out,rec.get('file',{}))

    summary=rec.get('session',{}).get('',{})
    mani=rec.get('manifest',{}).get('',{})
    datasets=rec.get('dataset',{})
    metadata=rec.get('dataset_metadata',{})
    dataset_notes=rec.get('dataset_note',{})
    scripts=rec.get('script',{})
    script_executions=rec.get('script_execution',{})
    module_documentation=rec.get('module_documentation',{})

    global ACTIVE_NAV
    file_rels=[e['rel'] for e in file_entries]
    has_analysis=any(PurePosixPath(r).parts and PurePosixPath(r).parts[0]=='analysis' for r in file_rels) or any(ds.get('source_module','') for ds in datasets.values())
    has_graphs=any(e['ext'] in GRAPH_EXT for e in file_entries)
    has_docs=any(e['ext'] in MD_EXT for e in file_entries)
    ACTIVE_NAV={'overview','export'}
    if datasets: ACTIVE_NAV.update({'datasets','provenance'})
    if has_analysis: ACTIVE_NAV.add('analyses')
    if scripts or script_executions: ACTIVE_NAV.add('scripts')
    if has_graphs: ACTIVE_NAV.add('graphs')
    if has_docs or module_documentation: ACTIVE_NAV.add('documents')
    if file_entries: ACTIVE_NAV.add('files')

    # Datasets
    dslinks=[]; dataset_stats={}
    for dsid,ds in sorted(datasets.items()):
        rel=ds.get('path',''); src=session/rel if rel else None; body=''
        if rel and rel in mapping and src and src.is_file() and src.suffix.lower()=='.csv':
            csvbody,rows,cols=make_csv(dsid,ds,src,out,mapping[rel]); dataset_stats[dsid]=(rows,cols); body+=csvbody
        else:
            body+=f'<div class="card">{kv_table({k:ds.get(k,"") for k in ["id","kind","contract","format","path","source_module","source","sha256","created_at"]})}</div>'
            if rel in mapping: body+=f'<p><a href="../{h(mapping[rel])}">Open/download Dataset artifact</a></p>'
        if dsid in metadata: body+=f'<div class="card"><h2>Dataset Metadata</h2>{kv_table(metadata[dsid])}</div>'
        if dsid in dataset_notes and dataset_notes[dsid].get('markup'):
            body+=f'<div class="card"><h2>Related notes</h2><pre>{h(dataset_notes[dsid]["markup"])}</pre></div>'
        prov={k:v for k,v in ds.items() if k in ('source_module','source_raw','source_sha256','canonical_sha256','provenance','publication_request','created_at') and v}
        body+=f'<div class="card"><h2>Provenance</h2>{kv_table(prov)}</div>'
        fn=safe_name(dsid)+'_'+sha_text(dsid)+'.html'; write(out/'datasets'/fn,shell('Dataset: '+dsid,body,'../')); dslinks.append((dsid,fn,ds))
    body='<div class="card"><h2>Datasets</h2>'+('<ul class="dataset-list">'+''.join(f'<li><a href="{h(fn)}">{h(dsid)}</a> <span class="badge">{h(ds.get("contract") or ds.get("kind"))}</span></li>' for dsid,fn,ds in dslinks)+'</ul>' if dslinks else '<p class="muted">No registered Datasets.</p>')+'</div>'
    write(out/'datasets'/'index.html',shell('Datasets',body,'../'))

    # Documents / notes
    doclinks=[]
    for e in file_entries:
        if e['ext'] not in MD_EXT: continue
        src=session/e['rel']
        try: text=src.read_text(encoding='utf-8')
        except UnicodeDecodeError: continue
        fn='doc_'+sha_text(e['rel'])+'.html'; write(out/'documents'/fn,shell('Document: '+e['rel'],markdown_page(e['rel'],text,e['copied']),'../'));doclinks.append((e['rel'],fn))
    manual_rows=[]
    for identity,record in sorted(module_documentation.items()):
        rel=record.get('manual_path','')
        if rel not in mapping: continue
        fn='doc_'+sha_text(rel)+'.html'
        manual_rows.append(f'<li><a href="{h(fn)}">{h(record.get("documentation.module_name") or record.get("documentation.module_id") or identity)}</a>'
                           f' — plugin version {h(record.get("documentation.module_version",""))}'
                           f' — SHA-256 <code>{h(record.get("documentation.sha256",""))}</code></li>')
    manual_section=('<div class="card"><h2>Module manuals captured with this Session</h2><ul>'+''.join(manual_rows)+'</ul></div>'
                    if manual_rows else '<div class="card"><h2>Module manuals</h2><p class="muted">No versioned manual snapshots are recorded in this Session. Installed manuals may describe a different plugin version.</p></div>')
    dbody=manual_section+'<div class="card"><h2>Markdown and Session notes</h2>'+('<ul>'+''.join(f'<li><a href="{h(fn)}">{h(r)}</a></li>' for r,fn in doclinks)+'</ul>' if doclinks else '<p class="muted">No Markdown documents.</p>')+'</div>'
    write(out/'documents'/'index.html',shell('Documentation / Notes',dbody,'../'))

    # Graphs
    graph_notes=graph_note_associations(session)
    glinks=[]
    for e in file_entries:
        if e['ext'] not in GRAPH_EXT: continue
        shown=e['copied']; clean=None
        if e['ext']=='.png':
            source=session/e['rel']
            annotation=source.parent/'annotations'/(source.stem+'.json')
            if annotation.is_file():
                document=json.loads(annotation.read_text(encoding='utf-8'))
                if document.get('enabled', True) and any(isinstance(item,dict) and item.get('visible',True) for item in document.get('objects',[])):
                    renderer=annotation_renderer or Path(__file__).resolve().parents[4]/'services'/'annotations'/'plot_annotation_renderer.py'
                    if not renderer.is_file(): raise ValueError(f'GX-TXT annotation compositor is unavailable: {renderer}')
                    annotated=PurePosixPath('graphs','images','annotated_'+sha_text(e['rel'])+'.png')
                    destination=out/Path(annotated.as_posix());destination.parent.mkdir(parents=True,exist_ok=True)
                    subprocess.run([sys.executable,str(renderer),'--base',str(source),'--annotations',str(annotation),'--output',str(destination)],check=True,capture_output=True,text=True)
                    shown=annotated.as_posix();clean=e['copied']
        note_rel=graph_notes.get(e['rel'])
        if note_rel is None:
            for prefix,associated in graph_notes.items():
                if prefix.endswith('/') and e['rel'].startswith(prefix):note_rel=associated;break
        note_text=None
        if note_rel in mapping:
            note_text=(session/note_rel).read_text(encoding='utf-8')
        fn='graph_'+sha_text(e['rel'])+'.html'; write(out/'graphs'/fn,shell('Graph: '+e['rel'],graph_page(e['rel'],shown,e['copied'],e['ext']=='.svg',clean,note_text),'../'));glinks.append((e['rel'],fn))
    gbody='<div class="card"><h2>Existing graph/image artifacts</h2>'+('<ul>'+''.join(f'<li><a href="{h(fn)}">{h(r)}</a></li>' for r,fn in glinks)+'</ul>' if glinks else '<p class="muted">No graph/image artifacts found.</p>')+'</div>'
    write(out/'graphs'/'index.html',shell('Graphs',gbody,'../'))

    # Text views and generic file list
    file_rows=[]
    for e in file_entries:
        viewer=''
        if e['ext'] in MD_EXT:
            viewer='../documents/doc_'+sha_text(e['rel'])+'.html'
        elif e['ext'] in GRAPH_EXT:
            viewer='../graphs/graph_'+sha_text(e['rel'])+'.html'
        elif e['ext'] in TEXT_EXT:
            try:text=(session/e['rel']).read_text(encoding='utf-8')
            except UnicodeDecodeError:text='[File is not valid UTF-8 and is available only for download.]'
            fn='text_'+sha_text(e['rel'])+'.html';write(out/'files'/fn,shell('Text: '+e['rel'],f'<div class="text-view card"><pre>{h(text)}</pre><p><a href="../{h(e["copied"])}" download>Open/download original</a></p></div>','../'));viewer=fn
        elif e['ext'] in CSV_EXT:
            # Prefer Dataset page if registered, otherwise download.
            for dsid,fn,ds in dslinks:
                if ds.get('path')==e['rel']: viewer='../datasets/'+fn;break
        link=f'<a href="{h(viewer)}">View</a>' if viewer else f'<a href="../{h(e["copied"])}" download>Open/download</a>'
        file_rows.append(f'<tr><td>{h(e["rel"])}</td><td>{e["size"]}</td><td><code>{h(e["sha256"])}</code></td><td>{link}</td></tr>')
    fbody='<div class="card"><div class="table-wrap"><table><thead><tr><th>Session file</th><th>Bytes</th><th>SHA-256</th><th>Action</th></tr></thead><tbody>'+''.join(file_rows)+'</tbody></table></div></div>'
    write(out/'files'/'index.html',shell('Files / Artifacts',fbody,'../'))

    # Analyses: use existing Session structure and public snapshot provenance only.
    analysis_modules=defaultdict(lambda:{'files':[],'datasets':[]})
    for e in file_entries:
        parts=PurePosixPath(e['rel']).parts
        if len(parts)>=2 and parts[0]=='analysis': analysis_modules[parts[1]]['files'].append(e)
    for dsid,ds in datasets.items():
        mid=ds.get('source_module','')
        if mid: analysis_modules[mid]['datasets'].append(dsid)
    blocks=[]
    for mid,data in sorted(analysis_modules.items()):
        lst=''.join(f'<li>{h(e["rel"])}</li>' for e in data['files'][:100])
        if len(data['files'])>100: lst+='<li>… additional files listed in Files / Artifacts</li>'
        dss=''.join(f'<span class="badge">{h(d)}</span>' for d in data['datasets']) or '<span class="muted">No registered output Dataset identified.</span>'
        blocks.append(f'<div class="card"><h2>{h(mid)}</h2><p>Produced/related Datasets: {dss}</p><details><summary>Session artifacts ({len(data["files"])})</summary><ul>{lst}</ul></details></div>')
    write(out/'analyses'/'index.html',shell('Analyses',''.join(blocks) if blocks else '<p class="muted">No analysis artifacts found.</p>','../'))

    # Only Session-owned scripts enter the inspection snapshot. Their source
    # snapshots and execution artifacts are copied by the normal inventory.
    script_blocks=[]
    for script_id,script in sorted(scripts.items()):
        if script.get('scope')!='session': continue
        source_rel=f'scripts/registered/{script_id}/source.m'
        source_link=(f'<p><a href="../{h(mapping[source_rel])}" download>Download Session script source</a></p>'
                     if source_rel in mapping else '')
        fields={k:script.get(k,'') for k in ('id','name','language','description','version','revision','sha256','required_apis','source_scope','source_id','source_sha256')}
        params=sorted({key.split('.')[1] for key in script if key.startswith('parameter.') and len(key.split('.'))==3})
        parameter_rows=''.join('<tr><td>'+h(name)+'</td>'+''.join(f'<td>{h(script.get(f"parameter.{name}.{field}",""))}</td>'
                           for field in ('type','required','default','description'))+'</tr>' for name in params)
        parameter_table=('<table><thead><tr><th>Name</th><th>Type</th><th>Required</th><th>Default</th><th>Description</th></tr></thead><tbody>'
                         +parameter_rows+'</tbody></table>') if params else '<p class="muted">No declared parameters.</p>'
        runs=[(run_id,run) for run_id,run in sorted(script_executions.items())
              if run.get('execution.script_id')==script_id and run.get('execution.script_scope')=='session']
        run_rows=[]
        for run_id,run in runs:
            report_rel=f'analysis/scripts/{run_id}/execution.ini'
            report_link=(f' <a href="../{h(mapping[report_rel])}" download>Execution report</a>'
                         if report_rel in mapping else '')
            run_rows.append(f'<li><strong>{h(run_id)}</strong> — {h(run.get("execution.status",""))}'
                            f' — source SHA-256: {h(run.get("execution.script_sha256",""))}{report_link}</li>')
        run_section=('<h3>Executions</h3><ul>'+''.join(run_rows)+'</ul>') if runs else '<p class="muted">No recorded executions.</p>'
        script_blocks.append(f'<div class="card"><h2>{h(script.get("name") or script_id)}</h2>{kv_table(fields)}'
                             f'{source_link}<h3>Parameters</h3>{parameter_table}{run_section}</div>')
    write(out/'scripts'/'index.html',shell('Session scripts',''.join(script_blocks) if script_blocks else
          '<p class="muted">No registered Session scripts. User-library scripts are not part of this export.</p>','../'))

    # Provenance
    prov=[]
    for dsid,ds in sorted(datasets.items()):
        vals={k:ds.get(k,'') for k in ('source_module','source','source_raw','source_sha256','canonical_sha256','provenance','publication_request','created_at')}
        prov.append(f'<div class="card"><h2>{h(dsid)}</h2>{kv_table(vals)}</div>')
    write(out/'provenance'/'index.html',shell('Metadata / Provenance',''.join(prov) if prov else '<p class="muted">No Dataset provenance records.</p>','../'))

    experiment={
        'Session name':summary.get('session_name',''),
        'Project':summary.get('experiment_project',''),
        'Experiment':summary.get('experiment_name',''),
        'Date':summary.get('experiment_date',''),
        'Operator':summary.get('experiment_operator',''),
        'Tags':summary.get('experiment_tags',''),
        'Framework version':framework_version,
        'HTML export date':now(),
    }
    stats=f'<div class="grid"><div class="card"><strong>{len(datasets)}</strong><br>Datasets</div><div class="card"><strong>{len(analysis_modules)}</strong><br>Analysis/module groups</div><div class="card"><strong>{len(scripts)}</strong><br>Session scripts</div><div class="card"><strong>{len(glinks)}</strong><br>Graph/image artifacts</div><div class="card"><strong>{len(file_entries)}</strong><br>Session files</div></div>'
    intro='<p class="readonly">Read-only export. Browser sorting, filtering, zoom and pan never modify the GX-TXT Session.</p>'
    write(out/'index.html',shell('Session Overview',intro+stats+'<div class="card"><h2>Session</h2>'+kv_table(experiment)+'</div>',''))

    expinfo={'GX-TXT framework version':framework_version,'HTML exporter':'export.session_html '+module_version,'Session source identity':summary.get('session_name',''),'HTML export timestamp':now(),'Mode':'Read-only offline representation'}
    statement='<p class="warning"><strong>This HTML export is a read-only representation of a GX-TXT Session. It is not a substitute for the portable GX-TXT Session archive.</strong></p><p>No GX-TXT installation, Tcl/Tk, Octave, Python, installed plugin, local web server, CDN or internet connection is required to browse this exported copy.</p>'
    write(out/'export-info.html',shell('Export information',statement+'<div class="card">'+kv_table(expinfo)+'</div>',''))

    # A compact machine-readable export manifest is presentation provenance, not Session state.
    manifest={'format':'GX-TXT Session HTML Export','format_version':1,'framework_version':framework_version,'exporter':'export.session_html','exporter_version':module_version,'session_name':summary.get('session_name',''),'export_timestamp':now(),'read_only':True,'files':[{k:e[k] for k in ('rel','size','sha256','copied')} for e in file_entries]}
    write(out/'export-manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

    zip_path=''
    if make_zip:
        zip_path=str(zip_target)
        tmp=Path(zip_path+'.tmp-'+str(os.getpid()))
        with zipfile.ZipFile(tmp,'w',compression=zipfile.ZIP_DEFLATED,allowZip64=True) as zf:
            for p in sorted(out.rglob('*')):
                if p.is_file(): zf.write(p,(out.name+'/'+p.relative_to(out).as_posix()))
        os.replace(tmp,zip_path)
    return {'directory':str(out),'zip':zip_path,'file_count':str(len(file_entries)),'dataset_count':str(len(datasets)),'graph_count':str(len(glinks))}


def main(argv=None):
    ap=argparse.ArgumentParser();sub=ap.add_subparsers(dest='cmd',required=True);p=sub.add_parser('export');p.add_argument('--session',required=True);p.add_argument('--snapshot',required=True);p.add_argument('--output',required=True);p.add_argument('--module-version',required=True);p.add_argument('--framework-version',required=True);p.add_argument('--annotation-renderer');p.add_argument('--zip',action='store_true');a=ap.parse_args(argv)
    try:
        r=export_site(Path(a.session),Path(a.snapshot),Path(a.output),a.module_version,a.framework_version,a.zip,Path(a.annotation_renderer) if a.annotation_renderer else None)
        for k,v in r.items():print(f'{k}={v}')
        return 0
    except Exception as e:
        print('Session HTML Export error: '+str(e),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
