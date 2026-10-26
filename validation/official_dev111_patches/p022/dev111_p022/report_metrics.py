#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import argparse,csv,json,re,statistics,tkinter
p=argparse.ArgumentParser();p.add_argument('workspace',type=Path);p.add_argument('output',type=Path);a=p.parse_args();assert not a.output.exists();root=a.workspace;t=tkinter.Tcl()
def dictionary(value):
 v=t.splitlist(value);return dict(zip(v[::2],v[1::2]))
cases=['normal01/molecule02','normal02/molecule-hw','molecule-candidate-hardware01','molecule-candidate-hardware02','molecule-candidate-hardware03','molecule-candidate-software01','molecule-candidate-software02','molecule-candidate-auto01','molecule-comparable-baseline-hw01','molecule-comparable-baseline-sw01','molecule-comparable-candidate-hw01','molecule-comparable-candidate-sw01']
result={'molecule':{},'cad':{},'limitations':['GUI input/query overhead and execution-trace overhead are included where stated.','Native render spans include existing framebuffer capture; PNG spans include buffer copy, encoding and file operations.','Hardware baseline needed only the child pthread startup correction; uncorrected explicit Hardware crashed.']}
for case in cases:
 path=root/case
 if not (path/'DRAG.tsv.receipts').exists():continue
 frames=[]
 for row in t.splitlist((path/'DRAG.tsv.receipts').read_text()):
  words=t.splitlist(row);data=dictionary(words[2]);tim=dictionary(data.get('timings_ms',''))
  frames.append(dict(completed_us=int(words[0]),kind=words[1],operations=int(data.get('navigation_operations',0)),worker_ms=float(words[3]),**{k:float(v) for k,v in tim.items()}))
 traces=list(csv.DictReader((path/'DRAG.tsv').open(),delimiter='\t'));accepted=[]
 # The old pending dispatcher recursively calls Request. Count only actual
 # Navigate owners and their nested Request; otherwise baseline is overcounted.
 requests=[x for x in traces if x['command'].split('::')[-1]=='meshDatasetRequest']
 for row in traces:
  if row['command'].split('::')[-1]!='meshDatasetNavigate':continue
  start=int(row['start_us']);end=start+int(row['duration_us']);nested=[x for x in requests if start<=int(x['start_us']) and int(x['start_us'])+int(x['duration_us'])<=end]
  matches=[]
  for request in nested:
   match=re.search(r'\{navigate (orbit|pan|roll|zoom) ([-+.eE0-9]+) ([-+.eE0-9]+)',request['arguments'])
   if match:matches.append(match)
  assert len(matches)==1,(case,row,matches)
  match=matches[0];accepted.append(dict(mode=match[1],dx=float(match[2]),dy=float(match[3])))
 summaries={}
 for key in ['prepare','native_render','png_write','worker_ms']:
  values=[x[key] for x in frames if key in x]
  if values:summaries[key]=dict(min=min(values),median=statistics.median(values),max=max(values),samples=values)
 photo=[int(x['duration_us'])/1000 for x in traces if x['command'].split('::')[-1]=='image' and x['arguments'].startswith('create photo')]
 spans=[int(x['duration_us'])/1000 for x in traces if x['command'].split('::')[-1]=='meshDatasetReadable']
 data=dict(frames=frames,summary_ms=summaries,accepted_navigation=accepted,accepted_count=len(accepted),native_operations=sum(x['operations'] for x in frames),total_dx=sum(x['dx'] for x in accepted),total_dy=sum(x['dy'] for x in accepted),photo_decode_ms=photo,readable_callback_ms=spans)
 for leaf,key in [('TIMES.json','observed_latency'),('PROCESS_COST.json','process_cost')]:
  if (path/leaf).exists():data[key]=json.loads((path/leaf).read_text())
 result['molecule'][case]=data
for case in ['cad-baseline01','cad-candidate03','cad-comparable-baseline01','cad-comparable-candidate01']:
 if not (root/case).exists():continue
 result['cad'][case]={}
 for count in [1,10,50]:
  path=root/case/f'objects{count}';values=json.loads((path/'TIMES.json').read_text());traces=list(csv.DictReader((path/'DRAG.tsv').open(),delimiter='\t'))
  values['render_method_spans_ms']=[int(x['duration_us'])/1000 for x in traces if x['command'].startswith('::oo::') and x['arguments']=='render'];values['trace_count']=len(traces)
  renders=[(int(x['start_us']),int(x['start_us'])+int(x['duration_us'])) for x in traces if x['command'].startswith('::oo::') and x['arguments']=='render']
  values['whole_host_render_ms']=[(b-a)/1000 for a,b in renders if not any(c<=a and b<=d and (c,d)!=(a,b) for c,d in renders)]
  values['native_detail_traced']=any(x['command'].split('::')[-1]=='core' for x in traces)
  values['scalar_world_calls']=sum(x['command'].split('::')[-1]=='core' and x['arguments'].startswith('world ') for x in traces)
  result['cad'][case][str(count)]=values
result['cad']['comparability']='Use cad-comparable-baseline01/candidate01 for the matched comparison: identical scientific fixtures and input, same viewport and current lightweight timing helper, no per-native-primitive traces. Other CAD cases are diagnostic only because trace overhead differs. Whole Host spans contain presenter spans; do not sum them. A zero scalar_world_calls with native_detail_traced false means not traced, not zero actual calls. Observed gesture times include deliberate input sleeps and query overhead; they are not photon latency.'
a.output.write_text(json.dumps(result,indent=2)+'\n');print('Wrote',a.output)
