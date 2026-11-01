# SPDX-License-Identifier: GPL-3.0-or-later
import base64,hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'core/python'))
from gxtxt_job_supervisor import tcl_result
from scientific_spectrum_import import source_sha
try:
 source=Path(base64.b64decode(sys.argv[1],validate=True).decode('utf-8'))
 context=source.parent/'gxtxt-library-entry.json'
 if not context.exists():result=dict(present=0,options={})
 else:
  if not context.is_file() or context.is_symlink() or context.stat().st_size>1048576:raise ValueError('Source context is not an admitted bounded ordinary file')
  with context.open('rb') as stream:raw=stream.read(1048577)
  if len(raw)>1048576:raise ValueError('Source context exceeds 1 MiB')
  value=json.loads(raw)
  if value.get('schema')!='gxtxt.library_acquisition_context.v1' or value.get('record_type')!='scientific.spectrum':raise ValueError('Unsupported scientific source context')
  if value.get('resource_sha256')!=source_sha(source):raise ValueError('Source context does not match exact source SHA')
  fields=value.get('fields',{});options=fields.get('parser_options')
  if not isinstance(options,dict) or len(options)>32 or any(not isinstance(k,str) for k in options):raise ValueError('Malformed spectrum source options')
  result=dict(present=1,options=options,format=fields.get('format',''),context_sha256=hashlib.sha256(raw).hexdigest())
 print(tcl_result(result))
except Exception as error:
 print(str(error),file=sys.stderr);sys.exit(1)
