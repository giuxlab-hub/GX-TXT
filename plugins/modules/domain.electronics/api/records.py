"""Source-preserving electronics records shared by independent suppliers."""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import json
import re
from scientific_library_manager import now
from scientific_library_records import canonical

def stable(prefix,*parts):
    return prefix+'-'+hashlib.sha256(canonical(parts)).hexdigest()[:24]

def property_record(name,value,conditions=None):
    """Only lossless, explicitly marked normalization; original supplier text stays."""
    result=dict(source_name=str(name),source_value=value,conditions=conditions or {},normalization='not_interpreted')
    if isinstance(value,str):
        match=re.fullmatch(r'\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(pF|nF|[µμu]F|F|mΩ|Ω|ohm|kΩ|V|mV|A|mA|kHz|MHz|Hz)\s*',value)
        if match:
            factors={'pF':('capacitance','F',1e-12),'nF':('capacitance','F',1e-9),'µF':('capacitance','F',1e-6),'μF':('capacitance','F',1e-6),'uF':('capacitance','F',1e-6),'F':('capacitance','F',1),'mΩ':('resistance','ohm',1e-3),'Ω':('resistance','ohm',1),'ohm':('resistance','ohm',1),'kΩ':('resistance','ohm',1e3),'V':('voltage','V',1),'mV':('voltage','V',1e-3),'A':('current','A',1),'mA':('current','A',1e-3),'Hz':('frequency','Hz',1),'kHz':('frequency','Hz',1e3),'MHz':('frequency','Hz',1e6)}
            quantity,unit,factor=factors[match[2]]
            result.update(quantity=quantity,value=float(match[1])*factor,unit=unit,normalization='explicit_simple_unit_v1')
    return result

def entry(record_type,fields,source_id,external_id,label='',raw=None):
    return dict(entry_id=stable(record_type.replace('.','-'),source_id,external_id),revision='1',record_type=record_type,
        label=label or external_id,fields=fields,resources=[],relations=[],
        provenance=dict(source_id=source_id,external_id=external_id,retrieved_at=now(),
            original_record_sha256=hashlib.sha256(canonical(raw if raw is not None else fields)).hexdigest(),normalization_version='1'))

def bundle(source_id,sku,manufacturer,mpn,category,properties,raw,media=None,offer=None,suggestions=None):
    if not all(isinstance(v,str) and v.strip() for v in (sku,manufacturer,mpn)):
        raise ValueError('Source component requires exact supplier SKU, manufacturer and MPN')
    part=entry('electronics.component',dict(manufacturer=manufacturer,mpn=mpn,category=category,
        properties=properties,supplier_listings=[dict(supplier=source_id,sku=sku)]),source_id,manufacturer+'|'+mpn,mpn,raw)
    part['content_contract']='electronics.component.record'
    listing=entry('electronics.supplier_listing',dict(supplier=source_id,sku=sku,manufacturer=manufacturer,mpn=mpn,source_record=raw,offer=offer or {}),source_id,sku,sku,raw)
    rows=[dict(library_type='electronics.components',entry=part),dict(library_type='electronics.components',entry=listing)]
    # Import resolves selected candidate keys to pinned Library references. Lookup
    # retains exact unresolved external references and never creates entities.
    def edge(relation,target_type,target_id,evidence,**extra):
        return dict(relation_type=relation,target=dict(kind='external_source_entity',source_id=source_id,external_id=target_id,record_type=target_type),
            source_id=source_id,assertion_kind='source',evidence=evidence,retrieved_at=now(),**extra)
    part['relations'].append(edge('electronics.sold_as','electronics.supplier_listing',sku,'Exact supplier listing returned for manufacturer and MPN'))
    for asset in (media or [])[:32]:
        if not isinstance(asset,dict) or not asset.get('url'):continue
        document=asset['role'] in ('datasheet','document','compliance')
        typ='technical.document' if document else 'technical.media'
        fields=dict(title=asset.get('title',asset['role']),source_url=asset['url'],**({'document_role':asset['role']} if document else {'media_role':asset['role']}))
        resource=entry(typ,fields,source_id,asset['url'],asset.get('title',asset['role']))
        resource['resources']=[dict(asset,availability='external')]
        resource['content_contract']='document.pdf' if document else 'image.raster'
        rows.append(dict(library_type='technical.resources',entry=resource))
        part['relations'].append(edge('electronics.has_document' if document else 'electronics.has_media',typ,asset['url'],'Source-linked '+asset['role']))
    alternatives=[]
    for item in (suggestions or [])[:20]:
        if not isinstance(item,dict) or not item.get('sku'):continue
        alternatives.append(item)
        part['relations'].append(edge('electronics.source_suggests_alternative','electronics.supplier_listing',item['sku'],item.get('evidence','Supplier suggested replacement'),native_class=item.get('native_class',''),engineering_compatibility='not_verified'))
    return dict(schema='gxtxt.library_source_bundle.v1',source_id=source_id,primary_entry_id=part['entry_id'],entries=rows,suggestions=alternatives,
        include_alternatives_default=False,session_datasets_created=0)
