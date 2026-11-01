"""LCSC documented Item Details adapter. No HTML scraping or order operations."""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import secrets
import time
import urllib.parse
from scientific_library_sources import credential_call,request,materialize_assets,transient_asset
CONNECTOR_ID='source.lcsc'
HOST='ips.lcsc.com'

def domain():
    path=Path(__file__).resolve().parents[2]/'domain.electronics/api/records.py'
    spec=importlib.util.spec_from_file_location('gxtxt_electronics_source_records',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def identity(value):
    if not isinstance(value,str) or not re.fullmatch(r'C[1-9][0-9]{0,11}',value):raise ValueError('LCSC lookup requires an exact C-number')
    return value

def auth_headers(raw,nonce=None,timestamp=None):
    """Official docs/index.html SHA1 algorithm; header auth from current docs.

    Credentials are protected opaque UTF8 JSON {key,secret}. Secret is never sent.
    Header names key/nonce/timestamp/signature follow current official docs.
    """
    try:
        value=json.loads(raw.decode('utf-8'));key=value['key'];secret=value['secret']
        if not isinstance(key,str) or not isinstance(secret,str) or not key or not secret:raise ValueError()
    except Exception:raise ValueError('LCSC protected profile requires JSON key and secret') from None
    nonce=nonce or secrets.token_hex(8);timestamp=timestamp or str(int(time.time()))
    text=f'key={key}&nonce={nonce}&secret={secret}&timestamp={timestamp}'
    return dict(key=key,nonce=nonce,timestamp=timestamp,signature=hashlib.sha1(text.encode()).hexdigest())

def fetch(sku):
    sku=identity(sku)
    def perform(secret):
        headers=auth_headers(secret)
        return json.loads(request('https://'+HOST+'/rest/wmsc2agent/product/info/'+sku,allowed_hosts={HOST},headers=headers,interval=2))
    return credential_call(perform)

def normalize(response,sku):
    identity(sku)
    if not isinstance(response,dict) or response.get('success') is not True or response.get('code') not in (200,'200'):
        code=response.get('code','unknown') if isinstance(response,dict) else 'schema'
        raise ValueError('LCSC API unavailable or rejected request; code='+str(code)[:12])
    product=response.get('result')
    if isinstance(product,list):
        if len(product)!=1:raise ValueError('LCSC exact lookup returned ambiguous products')
        product=product[0]
    if not isinstance(product,dict):raise ValueError('LCSC Item Details result schema changed')
    def field(*names):
        for name in names:
            if name in product:return product[name]
        return ''
    returned=field('lcsc_part_number','productCode','product_number')
    if returned!=sku:raise ValueError('LCSC returned SKU does not match requested identity')
    manufacturer=field('manufacturer','brandName','brand_name')
    if isinstance(manufacturer,dict):manufacturer=manufacturer.get('name','')
    mpn=field('mpn','productModel','manufacturer_part_number')
    attributes=field('parameters','paramVOList','attributes') or []
    if isinstance(attributes,dict):attributes=[dict(name=k,value=v) for k,v in attributes.items()]
    if not isinstance(attributes,list):raise ValueError('LCSC technical attribute shape changed')
    d=domain();properties=[]
    for item in attributes:
        if not isinstance(item,dict):raise ValueError('LCSC technical attribute is malformed')
        name=item.get('name',item.get('paramName',''));value=item.get('value',item.get('paramValue',''))
        if not name:raise ValueError('LCSC technical attribute has no source name')
        properties.append(d.property_record(name,value,item.get('conditions')))
    media=[]
    for name,role in [('datasheet_url','datasheet'),('pdfUrl','datasheet'),('product_image','photo'),('productImageUrl','photo'),('pinout_url','pinout'),('footprint_url','footprint_illustration')]:
        if product.get(name):media.append(dict(role=role,url=product[name]))
    for item in product.get('images',[]):
        if isinstance(item,str):media.append(dict(role='photo',url=item))
        elif isinstance(item,dict) and item.get('url'):media.append(dict(role=item.get('role','photo'),url=item['url']))
    suggestions=[]
    for item in product.get('alternatives',product.get('crossReferences',[])):
        if not isinstance(item,dict):raise ValueError('LCSC alternative schema changed')
        code=item.get('lcsc_part_number',item.get('sku',''))
        if code:
            identity(code);suggestions.append(dict(sku=code,native_class=item.get('type',item.get('class','')),evidence='LCSC source cross-reference: '+str(item.get('type',item.get('class','unspecified')))))
    offer={k:v for k,v in product.items() if k in {'stock','quantity','price','prices','currency','moq','availability','packaging'}}
    return d.bundle(CONNECTOR_ID,sku,manufacturer,mpn,str(field('category','catalogName')),properties,product,media,offer,suggestions)

def search(query,limit=50):
    bundle=normalize(fetch(identity(query)),query);part=bundle['entries'][0]['entry']
    return [dict(entry_id=query,metadata=dict(label=part['label'],manufacturer=part['fields']['manufacturer'],mpn=part['fields']['mpn']),provenance=dict(source_id=CONNECTOR_ID))]

def read(sku,options=None):
    bundle=normalize(fetch(identity(sku)),sku)
    bundle=transient_asset(bundle,options or {},{'www.lcsc.com', 'datasheet.lcsc.com', 'assets.lcsc.com', 'lcsc.com'})
    return materialize_assets(bundle,options or {},{'www.lcsc.com', 'datasheet.lcsc.com', 'assets.lcsc.com', 'lcsc.com'})
