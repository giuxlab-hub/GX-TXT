from pathlib import Path
import tkinter,sys,json,hashlib,statistics
base,candidate,destination=map(Path,sys.argv[1:4]);assert not destination.exists()
tcl=tkinter.Tcl()
def seq(x):return list(tcl.splitlist(x))
def dct(x):
    a=seq(x);return {str(a[i]):a[i+1] for i in range(0,len(a),2)}
def load(p):return p.read_text()
def numeric(x):
    try:return int(x)
    except (ValueError,TypeError):
        try:return float(x)
        except (ValueError,TypeError):return str(x)
def ndict(x):return {k:numeric(v) for k,v in dct(x).items()}
def stats(rows,key):
    values=[numeric(dct(r)[key]) for r in rows]
    return {'values':values,'mean':statistics.mean(values),'median':statistics.median(values),'max':max(values),'min':min(values)}
def read(out):
    clean=seq(load(out/'clean-redraws.tcllist'));attributed=dct(load(out/'redraw-attribution.tcldict'));allprofiles=dct(load(out/'profiles.tcldict'));fixture=dct(load(out/'fixture.tcldict'));source=dct(fixture['source'])
    p={}
    for key,raw in dct(allprofiles['profiles']).items():
        phase,name=seq(key);p.setdefault(phase,{})[name]=ndict(raw)
    frames=[ndict(x) for x in seq(allprofiles['frames'])]
    native={k:ndict(v) for k,v in dct(allprofiles['native']).items()}
    rawrun=json.loads(out.with_name(out.name+'.run.json').read_text())
    result={'path':str(out),'actual_exit_code':rawrun['code'],'clean':{k:stats(clean,k) for k in ['prepare_us','idle_paint_us','whole_us']},'attributed_redraw':{k:stats(seq(attributed['samples']),k) for k in ['prepare_us','idle_paint_us','whole_us']},'profiles':p,'native':native,'native_redraw':{k:ndict(v) for k,v in dct(attributed['native']).items()},'frames':frames,'top_owners':{phase:sorted([{'owner':k,**v} for k,v in owners.items()],key=lambda row:row['us'],reverse=True)[:15] for phase,owners in p.items()},'source':{k:str(v) for k,v in source.items()},'source_hash_current':hashlib.sha256(Path(str(source['path'])).read_bytes()).hexdigest(),'fixture':{k:numeric(fixture[k]) for k in ['scientific_spans','tk_items','native_objects']},'run_receipt':rawrun}
    result['source_unchanged']=result['source_hash_current']==str(source['sha256'])
    result['frame_by_phase']={phase:{'calls':len([r for r in frames if r['phase']==phase]),'sum_prepare_us':sum(r['prepare_us'] for r in frames if r['phase']==phase),'max_prepare_us':max((r['prepare_us'] for r in frames if r['phase']==phase),default=0)} for phase in p}
    final=out/'final.tcldict'
    if final.exists():
        f=dct(final.read_text());result['final']={k:numeric(f[k]) for k in ['tk_items','native_objects']};result['final']['history']=ndict(f['history']);result['final']['errors']=seq(f['errors']);result['final']['cubic']=str(f['cubic']);result['final']['joined']=str(f['joined'])
    return result,fixture
b,bfixture=read(base);c,cfixture=read(candidate)
record={'baseline':b,'candidate':c,'fixture50_geometry_exactly_equal':dct(bfixture['geometry'])==dct(cfixture['geometry']),'fixture50_count_equal':len(seq(bfixture['retained50']))==len(seq(cfixture['retained50'])),'source_payload_hash_equal':b['source_hash_current']==c['source_hash_current'],'clean_whole_mean_change_percent':100*(c['clean']['whole_us']['mean']/b['clean']['whole_us']['mean']-1),'warning':'Inclusive traced stage times overlap; do not add them. Clean redraw excludes diagnostics and synthetic input delays. Baseline final source-ID check typo preserves exit1 qualification; all preceding measurements and GUI assertions retained.'}
destination.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({k:v for k,v in record.items() if k not in ['baseline','candidate']},indent=2))
