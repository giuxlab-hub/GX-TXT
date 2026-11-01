# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded transport closure subordinate to the existing Portable Resource owner."""
import base64
import hashlib
import json
from pathlib import Path
import re
import tkinter

KEY = '_gxtxt.framework.document_assets_v1'
INDEX = 'document-assets.json'
SCHEMA = 'gxtxt.portable_document_assets.v1'

def fields(value):
    if not isinstance(value, str) or len(value.encode()) > 1048576:
        raise ValueError('Invalid bounded document asset dictionary')
    parts = tkinter.Tcl().splitlist(value)
    if len(parts) % 2 or len(set(parts[::2])) != len(parts)//2:
        raise ValueError('Invalid document asset dictionary fields')
    return dict(zip(parts[::2], parts[1::2]))

def reference(value):
    item = fields(value)
    if set(item) != {'api_id','document_id','owner_generation','sha256','size_bytes','metadata'}:
        raise ValueError('Invalid managed document asset reference')
    if item['api_id'] != 'INTERACTIVE_DOCUMENT_RESOURCE_API_v1' or not re.fullmatch(r'idoc_[0-9]{1,27}',item['document_id']):
        raise ValueError('Invalid managed document asset owner')
    if not re.fullmatch(r'[a-f0-9]{64}',item['sha256']) or not item['size_bytes'].isdigit() or not 0 < int(item['size_bytes']) <= 4194304:
        raise ValueError('Invalid managed document asset size or SHA')
    if not item['owner_generation'] or len(item['owner_generation'])>128 or re.search(r'[\x00\r\n]',item['owner_generation']):
        raise ValueError('Invalid managed document asset generation')
    metadata = fields(item['metadata'])
    if not metadata.get('format'):
        raise ValueError('Managed document asset needs its existing format metadata')
    return item

def assets(metadata):
    result = fields(metadata.get(KEY,''))
    if len(result)>32 or any(not re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]{0,95}',name) for name in result):
        raise ValueError('Invalid logical document asset names or count')
    total = 0
    for value in result.values(): total += int(reference(value)['size_bytes'])
    if total>16777216:
        raise ValueError('Document asset closure exceeds 16 MiB')
    return result

def load_plan(path):
    if path is None: return {}
    path = Path(path)
    if not path.is_file() or path.is_symlink() or path.stat().st_size>4194304:
        raise ValueError('Invalid public-owner document asset plan')
    values = {}
    for line in path.read_text().splitlines():
        key, encoded = line.split('\t')
        if key in values: raise ValueError('Duplicate asset plan field')
        values[key] = base64.b64decode(encoded,validate=True).decode('utf-8')
    if values.get('schema') != SCHEMA or not values.get('count','').isdigit() or int(values['count'])>4096:
        raise ValueError('Invalid document asset plan schema/count')
    result = {}
    expected = {'schema','count'}
    for index in range(1,int(values['count'])+1):
        prefix = f'asset.{index}.'
        names = {'dataset_id','name','reference','path'}
        expected.update(prefix+key for key in names)
        row = {key:values[prefix+key] for key in names}
        reference(row['reference'])
        by_name = result.setdefault(row['dataset_id'],{})
        if row['name'] in by_name: raise ValueError('Duplicate logical asset plan entry')
        by_name[row['name']] = row
    if set(values) != expected: raise ValueError('Unknown document asset plan field')
    return result

def export(builder, dataset_id, prefix, metadata, plan):
    declared = assets(metadata)
    if not declared: return
    admitted = plan.get(dataset_id,{})
    if set(admitted) != set(declared):
        raise ValueError('Document assets require their public Portable Resource host admission')
    index = {'schema':SCHEMA,'count':str(len(declared))}
    emitted = set()
    for ordinal,(name,raw) in enumerate(sorted(declared.items()),1):
        row = admitted[name];item = reference(raw)
        if row['reference'] != raw: raise ValueError('Document asset metadata changed after admission')
        path = builder.session/'metadata/interactive_document_resources'/item['document_id']/(item['sha256']+'.blob')
        if Path(row['path']) != path or any(part.is_symlink() for part in [path,*path.parents]) or not path.is_file():
            raise ValueError('Document asset path differs from its existing owner')
        if path.stat().st_size != int(item['size_bytes']) or hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:
            raise ValueError('Document asset bytes changed after admission')
        blob = 'assets/'+item['sha256']+'.blob'
        if blob not in emitted:
            builder.add(prefix+'/'+blob,'managed_document_asset',path);emitted.add(blob)
        for key,value in {'name':name,'reference':raw,'blob':blob}.items(): index[f'asset.{ordinal}.{key}'] = value
    builder.add(prefix+'/'+INDEX,'managed_document_assets',(json.dumps(index,sort_keys=True,indent=2)+'\n').encode())

def validate(archive, manifest, prefix, metadata):
    declared = assets(metadata)
    records = {item['path']:item for item in manifest['files'] if item['path'].startswith(prefix+'/') and item['role'] in {'managed_document_asset','managed_document_assets'}}
    index_path = prefix+'/'+INDEX
    if not declared:
        if records: raise ValueError('Unreferenced document assets are not portable Dataset authority')
        return
    if index_path not in records or records[index_path]['role']!='managed_document_assets' or records[index_path]['size']>1048576:
        raise ValueError('Document asset index is missing or exceeds bounds')
    index = json.loads(archive.read(index_path))
    if not isinstance(index,dict) or not all(isinstance(key,str) and isinstance(value,str) for key,value in index.items()) or index.get('schema')!=SCHEMA or index.get('count')!=str(len(declared)):
        raise ValueError('Invalid document asset index')
    used = {index_path};keys = {'schema','count'};seen = set()
    for ordinal in range(1,len(declared)+1):
        root = f'asset.{ordinal}.';keys.update(root+key for key in ('name','reference','blob'))
        name = index.get(root+'name');raw = index.get(root+'reference');blob = index.get(root+'blob')
        if name in seen or name not in declared or raw!=declared[name]: raise ValueError('Portable document asset association differs')
        seen.add(name);item = reference(raw)
        if blob!='assets/'+item['sha256']+'.blob': raise ValueError('Noncanonical document asset path')
        path = prefix+'/'+blob;record = records.get(path)
        if not record or record['role']!='managed_document_asset' or record['sha256']!=item['sha256'] or record['size']!=int(item['size_bytes']):
            raise ValueError('Portable document asset SHA/size differs')
        used.add(path)
    if set(index)!=keys or set(records)!=used:
        raise ValueError('Unknown or unreferenced document asset member')
