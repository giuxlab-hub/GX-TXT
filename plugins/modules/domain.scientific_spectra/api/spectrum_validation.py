# SPDX-License-Identifier: GPL-3.0-or-later
"""Delegates numeric source and scientific-axis admission to accepted CORE."""
import base64,hashlib,tempfile,tkinter
from pathlib import Path
from scientific_spectrum_import import parse_csv,parse_jcamp
from gxtxt_job_supervisor import tcl_result
def validate_entry(entry,framework):
 fields=entry['fields'];options=fields['parser_options']
 if not isinstance(options,dict):raise ValueError('Spectrum parser options must be a typed object')
 resources=[r for r in entry.get('resources',[]) if r.get('availability')=='local' and r.get('media_type') in {'text/csv','chemical/x-jcamp-dx'}]
 if len(resources)!=1:raise ValueError('A numeric Spectrum Library entry requires one actual CSV/JCAMP original')
 raw=base64.b64decode(resources[0]['data_base64'],validate=True)
 with tempfile.TemporaryDirectory(prefix='gxtxt-spectrum-library-') as temporary:
  path=Path(temporary)/('source.csv' if fields['format']=='csv' else 'source.jdx');path.write_bytes(raw)
  parser=parse_csv if fields['format']=='csv' else parse_jcamp
  opts=dict(options);metadata=opts.pop('metadata',{});provenance=opts.pop('provenance',{})
  scientific,metadata,provenance,pairs=parser(path,opts,metadata,provenance)
  scientific.update(metadata=metadata,provenance=provenance,x=[x for x,y in pairs],y=[y for x,y in pairs])
  interpreter=tkinter.Tcl()
  interpreter.eval('namespace eval ::GX {}')
  interpreter.createcommand('::GX::sha256File',lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest())
  interpreter.call('source',str(Path(framework)/'core/tcl/scientific_spectrum_api_v1.tcl'))
  try:interpreter.call('::GX::SpectrumAPIv1::create',tcl_result(scientific))
  except tkinter.TclError as error:raise ValueError(str(error)) from None
 if 'sample_count' in fields and fields['sample_count']!=len(pairs):raise ValueError('Spectrum sample count conflicts with actual source')
