# SPDX-License-Identifier: GPL-3.0-or-later
import base64,json,re,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'core'/'python'))
from gxtxt_job_supervisor import tcl_result
EXPECTED='electronics.component'
CONTRACT='electronics.component.record'
REQUIRED=['manufacturer', 'mpn']
def run():
 source=Path(base64.b64decode(sys.argv[1],validate=True).decode('utf-8'))
 raw=source.read_bytes()
 if len(raw)>16*1024*1024:raise ValueError('Structured record exceeds 16 MiB')
 def unique(pairs):
  out={}
  for k,v in pairs:
   if k in out:raise ValueError('Duplicate JSON field')
   out[k]=v
  return out
 value=json.loads(raw,object_pairs_hook=unique)
 if not isinstance(value,dict) or value.get('record_type')!=EXPECTED:raise ValueError('Wrong structured record type')
 fields=value.get('fields');provenance=value.get('provenance')
 if not isinstance(fields,dict) or not isinstance(provenance,dict) or not provenance.get('source_id'):raise ValueError('Missing structured fields or source provenance')
 if any(k not in fields for k in REQUIRED):raise ValueError('Missing required structured record fields')
 if EXPECTED=='electronics.component':
  if any(not isinstance(fields[k],str) or not fields[k].strip() for k in REQUIRED):raise ValueError('Manufacturer and MPN must be explicit strings')
  for prop in fields.get('properties',[]):
   if not isinstance(prop,dict) or not isinstance(prop.get('source_name'),str) or 'source_value' not in prop:raise ValueError('Malformed source technical property')
 elif EXPECTED=='scientific.publication':
  identifiers=fields['identifiers']
  if not isinstance(identifiers,dict) or not identifiers:raise ValueError('Publication requires at least one qualified identifier')
  for key,val in identifiers.items():
   if not isinstance(key,str) or not isinstance(val,str) or not val:raise ValueError('Invalid publication identifier')
   if key.lower().endswith('doi') and not re.fullmatch(r'10\.\d{4,9}/\S+',val,re.I):raise ValueError('Invalid DOI syntax')
   if key.lower().endswith('pmid') and not re.fullmatch(r'[1-9][0-9]*',val):raise ValueError('Invalid PMID syntax')
  if 'authors' in fields and (not isinstance(fields['authors'],list) or any(not isinstance(x,(str,dict)) for x in fields['authors'])):raise ValueError('Invalid ordered authors')
  if 'year' in fields and (type(fields['year']) is not int or not 1000<=fields['year']<=9999):raise ValueError('Invalid publication year')
 metadata={'record.type':EXPECTED,'record.fields_json':json.dumps(fields,ensure_ascii=False,allow_nan=False),'record.provenance_json':json.dumps(provenance,ensure_ascii=False,allow_nan=False)}
 for key in ('entry_id','revision','content_sha256'):
  if key in value:metadata['library.'+key]=str(value[key])
 result=dict(recognized=1,format=CONTRACT,contract=CONTRACT,metadata=metadata)
 if len(sys.argv)>2:
  output=Path(base64.b64decode(sys.argv[2],validate=True).decode('utf-8'));identity=sys.argv[3]
  if not re.fullmatch(r'[A-Za-z0-9_.-]+',identity) or identity in ('.','..'):raise ValueError('Invalid output Dataset identity')
  target=output/(identity+'.record.json')
  with target.open('xb') as stream:stream.write(raw)
  result['path']=target.name
 return result
try:print(tcl_result(run()))
except Exception as error:
 print(tcl_result(dict(recognized=0,error=str(error))));sys.exit(1)
