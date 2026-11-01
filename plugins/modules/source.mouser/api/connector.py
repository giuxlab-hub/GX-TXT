"""Independent Mouser Search API v1 part-number adapter; no cart/order API."""
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
import json
from pathlib import Path
import re
import urllib.parse
from scientific_library_sources import credential_call,request,materialize_assets,transient_asset
CONNECTOR_ID='source.mouser'
HOST='api.mouser.com'

def domain():
    path=Path(__file__).resolve().parents[2]/'domain.electronics/api/records.py'
    spec=importlib.util.spec_from_file_location('gxtxt_electronics_source_records',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def identity(sku):
    if not isinstance(sku,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/+\-]{0,149}',sku):raise ValueError('Mouser requires an exact qualified supplier part number')
    return sku

def fetch(sku):
    identity(sku)
    def perform(secret):
        # OWNER EXCEPTION 2026-10-28: documented apiKey is permitted in the
        # transient TLS query ONLY. No redirects, URL logging, persistence or
        # exception URL text. Existing protected scope owns secret lifetime.
        try:
            key=secret.decode('utf-8').strip()
            if not re.fullmatch(r'[A-Za-z0-9-]{16,128}',key):raise ValueError()
        except Exception:raise ValueError('Mouser protected profile requires the issued API key') from None
        url='https://'+HOST+'/api/v1/search/partnumber?'+urllib.parse.urlencode({'apiKey':key})
        body=json.dumps({'SearchByPartRequest':{'mouserPartNumber':sku,'partSearchOptions':'1'}}).encode()
        return json.loads(request(url,allowed_hosts={HOST},data=body,headers={'Content-Type':'application/json'},interval=2))
    return credential_call(perform)

def normalize(response,sku):
    identity(sku)
    if not isinstance(response,dict) or response.get('Errors'):raise ValueError('Mouser API rejected request or response schema changed')
    result=response.get('SearchResults')
    if not isinstance(result,dict) or not isinstance(result.get('Parts'),list):raise ValueError('Mouser SearchResults schema changed')
    parts=[part for part in result['Parts'] if isinstance(part,dict) and part.get('MouserPartNumber')==sku]
    if len(parts)!=1:raise ValueError('Mouser exact supplier SKU is absent or ambiguous')
    part=parts[0];d=domain();properties=[]
    for item in part.get('ProductAttributes',[]):
        if not isinstance(item,dict) or not item.get('AttributeName'):raise ValueError('Mouser technical attributes schema changed')
        properties.append(d.property_record(item['AttributeName'],item.get('AttributeValue',''),item.get('Conditions')))
    for name in ('Description','Category','ROHSStatus','LifecycleStatus','LeadTime'):
        if part.get(name):properties.append(d.property_record(name,part[name]))
    media=[]
    for name,role in [('ImagePath','photo'),('DataSheetUrl','datasheet')]:
        if part.get(name):media.append(dict(role=role,url=part[name]))
    replacements=part.get('SuggestedReplacement',part.get('SuggestedReplacements',[]))
    if isinstance(replacements,str):replacements=[replacements] if replacements else []
    if not isinstance(replacements,list):raise ValueError('Mouser replacement schema changed')
    suggestions=[]
    for item in replacements[:20]:
        if isinstance(item,str):candidate=item
        elif isinstance(item,dict):candidate=item.get('MouserPartNumber','')
        else:raise ValueError('Mouser replacement item schema changed')
        if candidate:suggestions.append(dict(sku=identity(candidate),native_class='Suggested Replacement',evidence='Mouser Search API Suggested Replacement; engineering compatibility not verified'))
    offer={k:v for k,v in part.items() if k in {'Availability','PriceBreaks','Min','Mult','Packaging','FactoryStock','Reeling','AvailabilityInStock'}}
    bundle=d.bundle(CONNECTOR_ID,sku,part.get('Manufacturer',''),part.get('ManufacturerPartNumber',''),part.get('Category',''),properties,part,media,offer,suggestions)
    # Official Search API Terms section4 restrict API-content storage. This
    # affects this API channel only; independently user-supplied local records
    # and files never pass through this connector restriction.
    bundle['persistent_import_available']=False
    bundle['persistence_reason']='Mouser Search API is read-through under its published source interface conditions; use independent manual/local-file Library inputs for persistent work'
    return bundle

def search(query,limit=50):
    bundle=normalize(fetch(identity(query)),query);part=bundle['entries'][0]['entry']
    return [dict(entry_id=query,metadata=dict(label=part['label'],manufacturer=part['fields']['manufacturer'],mpn=part['fields']['mpn']),provenance=dict(source_id=CONNECTOR_ID))]

def read(sku,options=None):
    bundle=normalize(fetch(identity(sku)),sku)
    bundle=transient_asset(bundle,options or {},{'www.mouser.it', 'www.mouser.co.uk', 'www.mouser.com', 'eu.mouser.com'})
    return materialize_assets(bundle,options or {},{'www.mouser.it', 'www.mouser.co.uk', 'www.mouser.com', 'eu.mouser.com'})
