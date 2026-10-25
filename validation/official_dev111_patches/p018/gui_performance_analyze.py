from pathlib import Path
import json,sys,statistics,tkinter
before,after,destination=map(Path,sys.argv[1:4]);assert not destination.exists()
tcl=tkinter.Tcl()
def dictionary(value):
    values=tcl.splitlist(value)
    return {str(values[n]):values[n+1] for n in range(0,len(values),2)}
def number_rows(value):
    return {k:{a:float(b) for a,b in dictionary(v).items()} for k,v in dictionary(value).items()}
def load(root):
    clean=[dictionary(row) for row in tcl.splitlist((root/'clean-redraws.tcllist').read_text())]
    result={'clean':{key:{'samples_ms':[float(row[key])/1000 for row in clean],'median_ms':statistics.median(float(row[key])/1000 for row in clean),'max_ms':max(float(row[key])/1000 for row in clean)} for key in ['prepare_us','paint_idle_us','whole_us']}}
    for name in ['redraw-attribution','wheel','translation']:
        receipt=dictionary((root/(name+'.tcldict')).read_text());frames=[dictionary(row) for row in tcl.splitlist(receipt['frames'])]
        ms=[(int(row['painted_us'])-int(row['begin_us']))/1000 for row in frames]
        result[name]={'profiles':number_rows(receipt['profiles']),'native':number_rows(receipt['native']),'frames_ms':ms,'frame_median_ms':statistics.median(ms),'frame_max_ms':max(ms)}
    fixture=dictionary((root/'fixture.tcldict').read_text());final=dictionary((root/'final.tcldict').read_text());result['fixture']={'retained':int(fixture['retained_count']),'spans':int(fixture['spans']),'native_objects':int(fixture['native_objects']),'tk_items':int(fixture['tk_items']),'sprites':{k:int(v) if str(v).isdigit() else str(v) for k,v in dictionary(fixture['native_sprites']).items()},'source_sha256':str(dictionary(fixture['source_payload'])['sha256']),'native_view':str(fixture['view'])};result['final_tk_items']=int(final['tk_items'])
    return result,fixture
b,bf=load(before);a,af=load(after)
report={'p017':b,'p018':a,'equivalence':{'native_definitions_exact':str(bf['geometry'])==str(af['geometry']),'native_view_exact':str(bf['view'])==str(af['view']),'canonical_source_sha256_equal':b['fixture']['source_sha256']==a['fixture']['source_sha256']},'limitations':['Few samples; noisy differences are not performance claims.','Tcl attribution totals are inclusive and overlap; do not sum nested rows.','Complete frame is _draw preparation plus Tk idle raster/paint completion on local X11.','GUI event frame receipts are instrumented and measured separately from clean samples.']}
destination.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'equivalence':report['equivalence'],'p017_clean':b['clean'],'p018_clean':a['clean']},indent=2))
