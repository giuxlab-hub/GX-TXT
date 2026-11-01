"""Provider-neutral typed entities, immutable Library transactions and graph index.

Registry authority is scientific_library_manager. SQLite below is disposable,
fingerprinted search/index data; immutable package entries own every assertion.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import base64
import configparser
import csv
import hashlib
import io
import json
import mimetypes
from pathlib import Path
import re
import sqlite3
import tempfile
import uuid
import zipfile
import scientific_library_manager as manager
from scientific_library_records import canonical, entry_hash, load

MAX_ENTRIES = 100
MAX_FILE = 32 * 1024 * 1024

def declarations(section):
    found = {}
    for descriptor in manager.provider_descriptors():
        parser = configparser.ConfigParser(interpolation=None, strict=True)
        parser.read(descriptor, encoding='utf-8')
        if not parser.has_section(section):
            continue
        identity = manager.safe_id(parser.get('meta','id'))
        if identity != descriptor.parent.name or parser.get(section,'api_version') != '1':
            raise ValueError('Invalid Library provider declaration')
        relative = Path(parser.get(section,'schema' if section == 'library_domain_provider' else 'entrypoint'))
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Unsafe Library provider declaration path')
        path = (descriptor.parent / relative).resolve()
        if not path.is_relative_to(descriptor.parent.resolve()) or not path.is_file():
            raise ValueError('Library provider declaration is absent')
        if identity in found:
            raise ValueError('Duplicate Library provider identity')
        found[identity] = dict(id=identity,version=parser.get('meta','version'),path=path,
            descriptor=descriptor, fields=dict(parser.items(section)))
    return found

def declared_content_contract(definition, fields=None):
    """Resolve a provider's literal representation selector, never an evaluator.

    Absence preserves the original fixed content_contract vocabulary. A selector
    only describes acquisition eligibility; it grants no Dataset authority.
    """
    selector=definition.get('content_contract_by_field')
    if selector is None:return definition.get('content_contract','')
    if not isinstance(selector,dict) or set(selector)!={'field','default','values'}:
        raise ValueError('Content contract selector requires field/default/values')
    field=selector['field'];description=definition.get('fields',{}).get(field,{}) if isinstance(field,str) else {}
    vocabulary=description.get('enum')
    if (description.get('type')!='string' or not isinstance(vocabulary,list) or not 1<=len(vocabulary)<=32
            or any(not isinstance(item,str) or not item or len(item)>128 or any(c in item for c in '\x00\r\n') for item in vocabulary)
            or len(set(vocabulary))!=len(vocabulary)):
        raise ValueError('Content contract selector requires a bounded declared string enum')
    mapping=selector['values'];default=selector['default']
    if not isinstance(default,str) or default not in vocabulary or not isinstance(mapping,dict) or set(mapping)!=set(vocabulary):
        raise ValueError('Content contract selector mapping/default differs from declared enum')
    for contract in mapping.values():
        if (not isinstance(contract,str) or len(contract)>128 or
                (contract and not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.:+/-]*',contract))):
            raise ValueError('Content contract selector requires literal contract IDs or empty')
    if 'content_contract' in definition and definition['content_contract']!=mapping[default]:
        raise ValueError('Default representation contradicts the fixed content contract')
    selected=(fields or {}).get(field,default)
    if not isinstance(selected,str) or selected not in mapping:
        raise ValueError('Unknown Library representation selector value')
    return mapping[selected]

def schemas():
    result = dict(schema='gxtxt.library_domain_catalog.v1', providers={}, record_types={}, relations={})
    for identity, declaration in declarations('library_domain_provider').items():
        raw = declaration['path'].read_bytes()
        value = json.loads(raw)
        if value.get('schema') != 'gxtxt.library_domain.v1' or value.get('provider_id') != identity:
            raise ValueError('Domain schema identity mismatch')
        result['providers'][identity] = dict(version=declaration['version'],sha256=hashlib.sha256(raw).hexdigest())
        for category in ('record_types','relations'):
            for name, schema in value.get(category,{}).items():
                manager.safe_id(name)
                if '.' not in name or name in result[category] or not isinstance(schema,dict):
                    raise ValueError('Invalid or duplicate qualified domain schema')
                if category=='record_types':
                    declared_content_contract(schema)
                    _projection_spec(schema)
                result[category][name] = dict(schema,provider_id=identity,provider_version=declaration['version'],schema_sha256=hashlib.sha256(raw).hexdigest())
    return result

def _projection_spec(definition):
    """Literal metadata selectors only; not a parser or executable adapter."""
    spec=definition.get('normalized_projection')
    if spec is None:return None
    if (not isinstance(spec,dict) or set(spec)!={'api_version','fields','label_path','source_id_path'}
            or type(spec['api_version']) is not int or spec['api_version']!=1
            or not isinstance(spec['fields'],dict) or not 1<=len(spec['fields'])<=32
            or set(spec['fields'])!=set(definition.get('fields',{}))
            or definition.get('content_contract') or definition.get('validator')
            or definition.get('resource_contracts') or definition.get('content_contract_by_field')):
        raise ValueError('Read-only normalized projection requires a finite metadata-only schema')
    for path in [*spec['fields'].values(),spec['label_path'],spec['source_id_path']]:
        if (not isinstance(path,list) or not 1<=len(path)<=8 or path[0]!='metadata'
                or any(not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}',key) for key in path)):
            raise ValueError('Projection selectors require bounded literal metadata dictionary keys')
    return spec

def _projection_definition(record,catalog):
    candidates=[(name,definition) for name,definition in catalog['record_types'].items()
        if definition.get('normalized_projection') is not None
        and record['library_type'] in _schema_types(definition)
        and definition['provider_id']==record['provider_id']]
    if len(candidates)>1:raise ValueError('Ambiguous normalized Library projection')
    return candidates[0] if candidates else None

def _project_metadata(record,row,catalog):
    selected=_projection_definition(record,catalog)
    if not selected:raise ValueError('Provider has no declared normalized metadata projection')
    record_type,definition=selected;spec=_projection_spec(definition)
    def select(path):
        value=row
        for key in path:
            if not isinstance(value,dict) or key not in value:
                raise ValueError('Normalized metadata lacks a declared projection field')
            value=value[key]
        return value
    label=select(spec['label_path']);source=select(spec['source_id_path'])
    if any(not isinstance(value,str) or not value or len(value)>4096 for value in (label,source)):
        raise ValueError('Normalized projection requires literal label and source identities')
    provenance=dict(row.get('provenance',{}))
    # Never invent a measurement/source-retrieval timestamp or hash a local
    # installation/call time: identical immutable packages retain portable pins.
    provenance.update(source_id=source,external_id=row['entry_id'],
        retrieved_at=provenance.get('retrieved_at') or 'not_recorded',
        retrieval_basis='provider_provenance' if provenance.get('retrieved_at') else 'not_recorded_by_provider',
        library_id=record['library_id'],library_version=record['version'],
        payload_sha256=record['payload_sha256'],package_sha256=record['package_sha256'])
    entry=dict(entry_id=row['entry_id'],record_type=record_type,
        revision=hashlib.sha256(canonical([record['version'],record['payload_sha256'],definition['schema_sha256']])).hexdigest(),
        label=label,fields={name:select(path) for name,path in spec['fields'].items()},
        provenance=provenance,resources=[],relations=[],read_only=True,
        domain_schema=dict(provider_id=definition['provider_id'],provider_version=definition['provider_version'],sha256=definition['schema_sha256']))
    if len(canonical(entry))>1024*1024:raise ValueError('Projected metadata exceeds 1 MiB per entry')
    validate_entry(entry,record['library_type'],catalog)
    entry['content_sha256']=entry_hash(entry)
    return entry

SCOPE_KEYS = {'library_types','record_types','library_ids','provider_ids','source_ids'}

def normalize_scope(scope=None):
    """Literal query selectors, never an access grant or executable predicate."""
    if scope is None:return {}
    if not isinstance(scope,dict) or set(scope)-SCOPE_KEYS:
        raise ValueError('Library scope requires only declared stable-ID list dimensions')
    result={}
    for key,values in scope.items():
        if not isinstance(values,list) or len(values)>64:
            raise ValueError('Library scope axes require at most 64 distinct IDs')
        seen=set()
        for value in values:
            if not isinstance(value,str) or not value or (key=='source_ids' and len(value)>512) or any(c in value for c in ('\r','\n','\0')):
                raise ValueError('Library scope IDs must be bounded nonempty literal strings')
            if key!='source_ids':manager.safe_id(value)
            if value in seen:raise ValueError('Duplicate Library scope identity')
            seen.add(value)
        if seen:result[key]=sorted(seen)
    result={key:result[key] for key in sorted(result)}
    if len(canonical(result))>32768:raise ValueError('Library scope exceeds 32 KiB')
    return result

def _schema_types(definition):
    return definition.get('library_types',[definition['library_type']])

def _scope_record_types(scope,catalog):
    return {name for name,definition in catalog['record_types'].items()
        if (not scope.get('record_types') or name in scope['record_types'])
        and (not scope.get('provider_ids') or definition['provider_id'] in scope['provider_ids'])
        and (not scope.get('library_types') or set(_schema_types(definition))&set(scope['library_types']))}

def scope_allows_entry(scope,library_id,entry,library_type=None,catalog=None):
    scope=normalize_scope(scope)
    if not scope:return True
    catalog=catalog or schemas();definition=catalog['record_types'].get(entry.get('record_type'))
    if not definition or entry['record_type'] not in _scope_record_types(scope,catalog):return False
    if scope.get('library_ids') and library_id not in scope['library_ids']:return False
    if library_type is not None and scope.get('library_types') and library_type not in scope['library_types']:return False
    return not scope.get('source_ids') or entry.get('provenance',{}).get('source_id') in scope['source_ids']

def require_scope_entry(scope,library_id,entry,library_type=None,catalog=None):
    if not scope_allows_entry(scope,library_id,entry,library_type,catalog):
        raise ValueError('Library entry is outside this declared Browser scope; its source assertion is retained without opening or importing unrelated content')

def _scope_sql(scope,catalog=None):
    scope=normalize_scope(scope)
    if not scope:return [],[]
    catalog=catalog or schemas();clauses=[];args=[]
    types=sorted(_scope_record_types(scope,catalog))
    if not types:return ['0'],[]
    clauses.append('record_type IN ('+','.join('?' for _ in types)+')');args.extend(types)
    if scope.get('library_ids'):
        ids=scope['library_ids'];clauses.append('library_id IN ('+','.join('?' for _ in ids)+')');args.extend(ids)
    if scope.get('library_types'):
        ids=sorted(key for key,record in manager.load_registry(manager.managed_root())['libraries'].items()
            if record.get('library_type') in scope['library_types'])
        if not ids:clauses.append('0')
        else:clauses.append('library_id IN ('+','.join('?' for _ in ids)+')');args.extend(ids)
    if scope.get('source_ids'):
        ids=scope['source_ids'];clauses.append("json_extract(body,'$.provenance.source_id') IN ("+','.join('?' for _ in ids)+')');args.extend(ids)
    return clauses,args

def _scoped_connectors(scope,catalog=None):
    import scientific_library_sources as sources
    available=sources.connectors();scope=normalize_scope(scope)
    if not scope:return available
    catalog=catalog or schemas();eligible=_scope_record_types(scope,catalog)
    types={typ for key in eligible for typ in _schema_types(catalog['record_types'][key])}
    if scope.get('library_types'):types&=set(scope['library_types'])
    return {key:row for key,row in available.items()
        if (not scope.get('source_ids') or key in scope['source_ids']) and types&set(row['library_types'])
        and (not scope.get('record_types') and not scope.get('provider_ids') or eligible&set(row.get('record_types',[])))}

def scope_source_allowed(scope,record,catalog=None):
    scope=normalize_scope(scope)
    if not scope:return True
    if scope.get('library_ids') and record['library_id'] not in scope['library_ids']:return False
    return record.get('provider_config',{}).get('connector') in _scoped_connectors(scope,catalog)

def scope_bundle(bundle,scope):
    scope=normalize_scope(scope)
    if not scope:return bundle
    result=json.loads(canonical(bundle));catalog=schemas()
    original_rows=result.get('entries',[])
    primary=next((row for row in original_rows if row['entry']['entry_id']==result.get('primary_entry_id')),original_rows[0] if original_rows else {})
    source_sha=primary.get('entry',{}).get('provenance',{}).get('original_record_sha256')
    if source_sha:result['source_record_sha256']=source_sha
    result['entries']=[row for row in result.get('entries',[])
        if scope_allows_entry({k:v for k,v in scope.items() if k!='library_ids'},'',row['entry'],row['library_type'],catalog)]
    allowed={row['entry']['entry_id'] for row in result['entries']}
    if 'preview_assets' in result:result['preview_assets']=[asset for asset in result['preview_assets'] if asset.get('entry_id') in allowed]
    result['scope']=scope;result['scoped_entry_count']=len(result['entries'])
    # Suggestions are upstream identities awaiting their own explicit read; no
    # claim that they already contain an eligible scientific record.
    result['scope_note']='Typed preview is scoped; source search and suggestions identify upstream entities awaiting inspection'
    return result

def scope_describe(scope=None):
    scope=normalize_scope(scope);catalog=schemas();registry=manager.load_registry(manager.managed_root())['libraries']
    eligible=_scope_record_types(scope,catalog);diagnostics=[]
    known={'library_types':{typ for value in catalog['record_types'].values() for typ in _schema_types(value)},
        'record_types':set(catalog['record_types']),'provider_ids':set(catalog['providers']),'library_ids':{key for key,row in registry.items() if row.get('state')=='installed'}}
    import scientific_library_sources as sources
    known['source_ids']=set(sources.connectors())
    if scope.get('source_ids'):
        connection=_index()
        try:known['source_ids'].update(row[0] for row in connection.execute("SELECT DISTINCT json_extract(body,'$.provenance.source_id') FROM entries"))
        finally:connection.close()
    for key,values in scope.items():
        for value in values:
            if value not in known[key]:diagnostics.append(dict(axis=key,id=value,reason='Identity is not currently available; no fallback to unrestricted content'))
    # Library IDs constrain manual choices to actual currently registered types.
    if scope.get('library_ids'):
        types={registry[key]['library_type'] for key in scope['library_ids'] if key in registry and registry[key].get('state')=='installed'}
        eligible={key for key in eligible if set(_schema_types(catalog['record_types'][key]))&types}
    selected_types={key:row for key,row in catalog['record_types'].items() if key in eligible}
    selected_relations={key:row for key,row in catalog['relations'].items() if set(row['from_types']+row['to_types'])&eligible}
    selected_providers={row['provider_id'] for row in selected_types.values()}|{row['provider_id'] for row in selected_relations.values()}
    selected_catalog=dict(catalog,record_types=selected_types,
        providers={key:row for key,row in catalog['providers'].items() if key in selected_providers},
        relations=selected_relations)
    connectors=_scoped_connectors(scope,catalog)
    registrations=[]
    for key,record in sorted(registry.items()):
        if record.get('state')!='installed' or record.get('mode')!='remote' or not scope_source_allowed(scope,record,catalog):continue
        identity=record.get('provider_config',{}).get('connector','')
        if identity not in connectors:continue
        registrations.append(dict(library_id=key,display_name=record.get('display_name',key),library_type=record['library_type'],connector_id=identity))
    return dict(schema='gxtxt.library_scope.v1',scope=scope,restricted=bool(scope),
        eligible_record_types=sorted(eligible),catalog=selected_catalog,connectors=connectors,
        sources=registrations[:100],source_total=len(registrations),source_limit=100,diagnostics=diagnostics)

def _typed(value, definition):
    kind = definition.get('type','string')
    checks = dict(string=lambda:type(value) is str, number=lambda:type(value) in (float,int),
        integer=lambda:type(value) is int, boolean=lambda:type(value) is bool,
        object=lambda:type(value) is dict, array=lambda:type(value) is list,
        scalar=lambda:value is None or type(value) in (str,float,int,bool))
    if kind not in checks or not checks[kind]():
        raise ValueError('Domain field does not match declared type: '+kind)
    if 'enum' in definition and value not in definition['enum']:
        raise ValueError('Domain field is outside declared vocabulary')
    if kind=='array' and definition.get('editor')=='table':
        if len(value)>100:raise ValueError('Structured property table exceeds 100 rows')
        for row in value:
            if not isinstance(row,dict):raise ValueError('Structured property row must be an object')
            for key,column in definition['columns'].items():
                if column.get('required') and (key not in row or row[key]==''):
                    raise ValueError('Property row requires '+key)
                if key in row:_typed(row[key],column)

def validate_entry(entry, library_type, catalog=None):
    catalog = catalog or schemas()
    manager.safe_id(entry.get('entry_id',''))
    manager.safe_id(entry.get('revision',''))
    declaration = catalog['record_types'].get(entry.get('record_type'))
    if not declaration or library_type not in declaration.get('library_types',[declaration['library_type']]):
        raise ValueError('Unknown or incompatible Library record schema')
    pinned=entry.get('domain_schema')
    if pinned and (pinned.get('provider_id')!=declaration['provider_id'] or
            pinned.get('sha256') not in [declaration['schema_sha256'],*declaration.get('compatible_schema_sha256',[])]):
        raise ValueError('Saved domain schema version is unavailable; install a compatible provider or explicitly adapt a new Library version')
    fields = entry.get('fields')
    if not isinstance(fields,dict):
        raise ValueError('Library fields must be a typed dictionary')
    for key,definition in declaration.get('fields',{}).items():
        if definition.get('required') and key not in fields:
            raise ValueError('Missing required domain field: '+key)
        if key in fields:
            _typed(fields[key],definition)
    unknown = set(fields)-set(declaration.get('fields',{}))
    if unknown and not declaration.get('additional_fields',False):
        raise ValueError('Undeclared domain fields: '+', '.join(sorted(unknown)))
    if 'content_contract_by_field' in declaration:
        selected_contract=declared_content_contract(declaration,fields)
        if 'content_contract' in entry and entry['content_contract']!=selected_contract:
            raise ValueError('Entry content contract contradicts its declared representation')
    provenance = entry.get('provenance',{})
    if not isinstance(provenance,dict) or not provenance.get('source_id') or not provenance.get('retrieved_at'):
        raise ValueError('Library entry requires source identity and retrieval provenance')
    for resource in entry.get('resources',[]):
        if not isinstance(resource,dict) or not resource.get('role'):
            raise ValueError('Invalid Library resource declaration')
        if 'data_base64' in resource:
            raw=base64.b64decode(resource['data_base64'],validate=True)
            if len(raw)>MAX_FILE or hashlib.sha256(raw).hexdigest()!=resource.get('sha256'):
                raise ValueError('Library resource bytes/hash mismatch')
        elif not resource.get('url') or resource.get('availability')!='external':
            raise ValueError('Library resource must be stored bytes or explicit external link')
    for relation in entry.get('relations',[]):
        definition=catalog['relations'].get(relation.get('relation_type'))
        if not definition or entry['record_type'] not in definition['from_types']:
            raise ValueError('Unknown relation or incompatible source type')
        target=relation.get('target',{})
        if target.get('kind') not in {'library_entry','canonical_dataset','external_source_entity'}:
            raise ValueError('Invalid relation anchor kind')
        if target.get('record_type') not in definition['to_types']:
            raise ValueError('Relation target violates domain type constraint')
        for required in ('source_id','evidence','assertion_kind','retrieved_at'):
            if not relation.get(required):
                raise ValueError('Relation requires attributed evidence: '+required)
        if relation['assertion_kind'] not in {'source','user','derived'}:
            raise ValueError('Unknown relation assertion kind')
        if target['kind']=='library_entry':
            for key in ('library_id','entry_id','revision','content_sha256'):
                if not target.get(key):raise ValueError('Library relation must pin exact target '+key)
        elif target['kind']=='canonical_dataset':
            for key in ('session_id','dataset_id','revision'):
                if not target.get(key):raise ValueError('Dataset relation must pin exact '+key)
        elif not target.get('source_id') or not target.get('external_id'):
            raise ValueError('External relation requires qualified source identity')
    validator=declaration.get('validator')
    if validator:
        import importlib.util
        owner=declarations('library_domain_provider')[declaration['provider_id']]
        relative=Path(validator)
        path=(owner['descriptor'].parent/relative).resolve()
        if relative.is_absolute() or '..' in relative.parts or path.suffix!='.py' or not path.is_relative_to(owner['descriptor'].parent.resolve()):
            raise ValueError('Unsafe domain scientific validator path')
        spec=importlib.util.spec_from_file_location('gxtxt_library_domain_validation',path)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        module.validate_entry(entry,manager.FRAMEWORK)
    return declaration

def local_resource(path, role, source):
    path=Path(path).resolve()
    if not path.is_file() or path.stat().st_size>MAX_FILE:
        raise ValueError('Local Library resource is absent or exceeds 32 MiB')
    raw=path.read_bytes()
    if raw.startswith(b'%PDF-'):
        mime='application/pdf'
    elif raw.startswith(b'\x89PNG\r\n\x1a\n'):
        mime='image/png'
    elif raw.startswith(b'\xff\xd8\xff'):
        mime='image/jpeg'
    elif raw.startswith((b'GIF87a',b'GIF89a')):
        mime='image/gif'
    else:
        raise ValueError('Local attachment must be a genuine PDF, PNG, JPEG or GIF')
    return dict(role=role,original_filename=path.name,media_type=mime,source_id=source,
        availability='local',sha256=hashlib.sha256(raw).hexdigest(),size_bytes=len(raw),
        data_base64=base64.b64encode(raw).decode('ascii'))

def import_entries(library_id, library_type, entries, display_name='', expected_version=None):
    """Explicit Stage A transaction: data-only package -> existing install/update.

    Existing version is checked; concurrent commits fail via existing immutable
    version path, never silently overwrite. Previous package bytes are retained.
    """
    manager.safe_id(library_id)
    if not isinstance(entries,list) or not 1<=len(entries)<=MAX_ENTRIES:
        raise ValueError('Select between 1 and 100 entries for explicit Library import')
    if len({entry.get('entry_id') for entry in entries})!=len(entries):raise ValueError('Duplicate entry IDs in one Library selection')
    provider=manager.select_provider(library_type)
    catalog=schemas()
    if any(catalog['record_types'].get(entry.get('record_type'),{}).get('normalized_projection') is not None for entry in entries):
        raise ValueError('Projected managed metadata cannot be imported or rewritten as typed Library records')
    registry=manager.load_registry(manager.managed_root())
    old=registry['libraries'].get(library_id)
    if old and (old['state']!='installed' or old['library_type']!=library_type):
        raise ValueError('Destination Library identity/type is unavailable')
    if expected_version is not None and (old or {}).get('version','')!=expected_version:
        raise ValueError('Destination Library version changed; review selection again')
    payload=load(manager.storage_path(manager.managed_root(),old)) if old else dict(
        schema='gxtxt.library_records.v1',library_type=library_type,entries={},history=[])
    receipt=[]
    for original in entries:
        entry=json.loads(canonical(original))
        entry.setdefault('revision','1')
        previous=payload['entries'].get(entry['entry_id'])
        # Same stable ID may only update after the caller pins old content hash.
        if previous and entry.get('content_sha256')==previous['content_sha256'] and entry_hash({k:v for k,v in entry.items() if k!='expected_content_sha256'})==previous['content_sha256']:
            receipt.append(dict(entry_id=entry['entry_id'],status='unchanged',revision=previous['revision']))
            continue
        if previous:
            if entry.pop('expected_content_sha256',None)!=previous['content_sha256']:
                raise ValueError('Existing entry changed: explicit previous content SHA required')
            payload['history'].append(previous)
            entry['revision']=str(int(previous['revision'])+1)
        entry.pop('content_sha256',None)
        declaration=validate_entry(entry,library_type,catalog)
        entry['domain_schema']=dict(provider_id=declaration['provider_id'],provider_version=declaration['provider_version'],sha256=declaration['schema_sha256'])
        entry['content_sha256']=entry_hash(entry)
        payload['entries'][entry['entry_id']]=entry
        receipt.append(dict(entry_id=entry['entry_id'],status='updated' if previous else 'added',revision=entry['revision'],content_sha256=entry['content_sha256']))
    if old and all(row['status']=='unchanged' for row in receipt):
        return dict(schema='gxtxt.library_import_receipt.v1',library_id=library_id,version=old['version'],entries=receipt,
            transaction_id=uuid.uuid4().hex,session_datasets_created=0)
    version=str(int(old['version'].split('.')[0])+1)+'.0' if old else '1.0'
    manifest=dict(library_id=library_id,library_type=library_type,version=version,
        provider_id=provider['provider_id'],format_version='1',display_name=display_name or library_id,
        description='Explicit persistent typed Library records; independent of Sessions',
        license='Source-specific attribution retained per entry',origin='user-selected Library import')
    parser=configparser.ConfigParser(interpolation=None);parser['library']=manifest
    text=io.StringIO();parser.write(text)
    raw=canonical(payload)
    with tempfile.TemporaryDirectory(prefix='gxtxt-library-package-') as temporary:
        path=Path(temporary)/'library.zip'
        with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('library.ini',text.getvalue())
            archive.writestr('payload/library.gxsrl',raw)
            archive.writestr('SHA256SUMS.txt',hashlib.sha256(raw).hexdigest()+'  payload/library.gxsrl\n')
        info=manager.install_or_update('update' if old else 'install',path,library_id if old else None,
            expected_version=old['version'] if old else '')
    return dict(schema='gxtxt.library_import_receipt.v1',library_id=library_id,version=info['version'],entries=receipt,
        transaction_id=uuid.uuid4().hex,session_datasets_created=0)

def read_pinned(reference, scope=None):
    record=manager.require_installed(manager.load_registry(manager.managed_root()),reference['library_id'])
    provider=manager.select_provider(record['library_type'],record['provider_id'])
    catalog=schemas()
    if getattr(provider['module'],'TYPED_RECORDS',False):
        manager._verify_managed_record(manager.managed_root(),record,provider)
        entry=load(manager.storage_path(manager.managed_root(),record))['entries'].get(reference['entry_id'])
    else:
        if not _projection_definition(record,catalog):raise ValueError('Library has no declared metadata projection')
        row=manager._library_content(record['library_id'],'entry_info',dict(entry_id=reference['entry_id']))
        current=manager.require_installed(manager.load_registry(manager.managed_root()),record['library_id'])
        if current!=record:raise ValueError('Library registration changed during inspection')
        entry=_project_metadata(record,row,catalog)
    if not entry or entry.get('tombstone'):
        raise ValueError('Library entry is missing/tombstoned')
    if any(reference.get(key,entry[key])!=entry[key] for key in ('revision','content_sha256')):
        raise ValueError('Saved Library entry revision/hash is stale')
    validate_entry(entry,record['library_type'],catalog)
    if entry_hash(entry)!=entry['content_sha256']:raise ValueError('Library entry hash mismatch')
    require_scope_entry(scope,record['library_id'],entry,record['library_type'])
    return entry

def import_bundle(bundle, selected_ids, destinations):
    """Reviewed, nonrecursive subset; cross-Library batches report each commit."""
    if bundle.get('schema')!='gxtxt.library_source_bundle.v1' or not isinstance(selected_ids,list) or not 1<=len(selected_ids)<=MAX_ENTRIES or len(set(selected_ids))!=len(selected_ids):
        raise ValueError('Review 1 to 100 distinct source records before Library import')
    rows={row['entry']['entry_id']:json.loads(canonical(row)) for row in bundle['entries']}
    if set(selected_ids)-set(rows):raise ValueError('Source selection includes an absent entry')
    selected=[rows[key] for key in selected_ids]
    catalog=schemas();resolved={};receipts=[]
    # Leaves precede semantic parents. Relations to unselected resources stay
    # explicitly external; no graph traversal triggers an implicit import.
    selected.sort(key=lambda row:len(row['entry'].get('relations',[])))
    groups={};existing={}
    registry=manager.load_registry(manager.managed_root())
    for destination in set(destinations.values()):
        record=registry['libraries'].get(destination)
        if record and record.get('state')=='installed':
            existing[destination]=load(manager.storage_path(manager.managed_root(),record))['entries']
    def comparable(value):
        if isinstance(value,dict):return {k:comparable(v) for k,v in value.items() if k not in {'retrieved_at','revision','content_sha256','expected_content_sha256'}}
        if isinstance(value,list):return [comparable(v) for v in value]
        return value
    for row in selected:
        typ=row['library_type'];destination=destinations.get(typ)
        if not destination:raise ValueError('Choose a destination Library for '+typ)
        manager.safe_id(destination)
        entry=row['entry']
        for edge in entry.get('relations',[]):
            target=edge['target'];key=(target.get('source_id'),target.get('external_id'),target.get('record_type'))
            if key in resolved:edge['target']=resolved[key]
        definition=validate_entry(entry,typ,catalog)
        entry['domain_schema']=dict(provider_id=definition['provider_id'],provider_version=definition['provider_version'],sha256=definition['schema_sha256'])
        previous=existing.get(destination,{}).get(entry['entry_id'])
        if previous:
            if comparable(previous)==comparable(entry):entry=previous
            else:
                entry['revision']=str(int(previous['revision'])+1)
                entry['expected_content_sha256']=previous['content_sha256']
        entry['content_sha256']=entry_hash(entry)
        # expected_content_sha256 is an admission precondition, not scientific
        # content. import_entries consumes it before hashing the saved revision.
        if 'expected_content_sha256' in entry:
            entry['content_sha256']=entry_hash({k:v for k,v in entry.items() if k!='expected_content_sha256'})
        provenance=entry['provenance']
        resolved[(provenance['source_id'],provenance.get('external_id'),entry['record_type'])]=dict(kind='library_entry',
            library_id=destination,entry_id=entry['entry_id'],record_type=entry['record_type'],revision=entry['revision'],content_sha256=entry['content_sha256'])
        groups.setdefault((destination,typ),[]).append(entry)
    # Order batches by first dependent record; preceding leaf batch commits
    # remain visible if a later independent Library transaction fails.
    for (destination,typ),entries in groups.items():
        try:receipts.append(dict(status='completed',result=import_entries(destination,typ,entries)))
        except Exception as error:
            receipts.append(dict(status='failed',library_id=destination,error=str(error)))
            break
    return dict(schema='gxtxt.library_source_import.v1',batches=receipts,
        status='completed' if all(row['status']=='completed' for row in receipts) else 'partial' if len(receipts)>1 else 'failed',session_datasets_created=0)

def detail(reference, scope=None):
    entry=json.loads(canonical(read_pinned(reference,scope)))
    for resource in entry.get('resources',[]):resource.pop('data_base64',None)
    return entry

def stage(reference, resource_index, output_dir, scope=None):
    """Copy pinned bytes into a host Resource Management allocation, no parser."""
    entry=read_pinned(reference,scope)
    output=Path(output_dir).resolve()
    if not output.is_dir():raise ValueError('Owned Resource Management allocation is absent')
    contract=entry.get('content_contract','')
    if resource_index == -1:
        if not entry.get('content_contract'):raise ValueError('Entry has no declared acquisition representation')
        raw=canonical(entry);name='record.json';mime='application/json'
    else:
        if type(resource_index) is not int or resource_index<0 or resource_index>=len(entry.get('resources',[])):
            raise ValueError('Choose an actual local Library resource')
        resource=entry['resources'][resource_index]
        if resource.get('availability')!='local' or 'data_base64' not in resource:
            raise ValueError('External resource has no locally stored bytes')
        raw=base64.b64decode(resource['data_base64'],validate=True)
        name=Path(resource.get('original_filename','resource.bin')).name
        if hashlib.sha256(raw).hexdigest()!=resource['sha256']:raise ValueError('Pinned resource SHA changed')
        mime=resource['media_type']
        definition=schemas()['record_types'][entry['record_type']]
        contract=resource.get('content_contract',definition.get('resource_contracts',{}).get(mime,''))
    path=output/name
    if path.exists():raise ValueError('Staging destination already exists')
    with path.open('xb') as stream:stream.write(raw)
    result=dict(source_path=str(path),sha256=hashlib.sha256(raw).hexdigest(),media_type=mime,
        content_contract=contract,library_id=reference['library_id'],entry_id=entry['entry_id'],
        revision=entry['revision'],content_sha256=entry['content_sha256'],source_id=entry['provenance']['source_id'])
    definition=schemas()['record_types'][entry['record_type']]
    selected_fields=definition.get('acquisition_context_fields',[])
    if selected_fields:
        fields={key:entry['fields'][key] for key in selected_fields if key in entry['fields']}
        context=canonical(dict(schema='gxtxt.library_acquisition_context.v1',record_type=entry['record_type'],
            reference=dict(library_id=reference['library_id'],entry_id=entry['entry_id'],revision=entry['revision'],content_sha256=entry['content_sha256']),
            resource_sha256=result['sha256'],fields=fields))
        if len(context)>1048576:raise ValueError('Library acquisition context exceeds 1 MiB')
        context_path=output/'gxtxt-library-entry.json'
        with context_path.open('xb') as stream:stream.write(context)
        result.update(context_path=str(context_path),context_sha256=hashlib.sha256(context).hexdigest())
    return result

def manual_prepare(record_type, fields, source_id, label='', entry_id='', pasted_text='', attachments=None, previous=None, raw_fields=False,
        suggestions=None, library_id='', expected_version=None, scope=None):
    catalog=schemas();definition=catalog['record_types'].get(record_type)
    if not definition:raise ValueError('Choose an installed Library record schema')
    if definition.get('normalized_projection') is not None:raise ValueError('This schema is a read-only view of managed provider metadata, not a manual record format')
    normalized_scope=normalize_scope(scope)
    if normalized_scope and record_type not in _scope_record_types(normalized_scope,catalog):raise ValueError('Manual record schema is outside this declared Browser scope')
    if not isinstance(source_id,str) or not source_id.strip() or len(source_id)>4096:raise ValueError('Enter source identity for the manual record')
    if not isinstance(pasted_text,str) or len(pasted_text)>262144:raise ValueError('Pasted specifications exceed 256 KiB')
    fields=json.loads(canonical(fields))
    if raw_fields:
        converted={}
        for key,value in fields.items():
            if value=='':continue
            kind=definition.get('fields',{}).get(key,{}).get('type')
            converted[key]=value if kind=='string' else json.loads(value)
        fields=converted
    prior_entry=read_pinned(previous,normalized_scope) if previous else None
    unchanged_paste=bool(prior_entry is not None and pasted_text==prior_entry['provenance'].get('original_text',''))
    paste=definition.get('paste')
    # An Edit form restores the original paste alongside already reviewed typed
    # fields. Reparse only a changed paste; replaying it would replace edits to
    # the technical rows with the older source transcription.
    if pasted_text and paste and not unchanged_paste:
        values=[]
        for line in pasted_text.splitlines():
            if not line.strip():continue
            name,separator,value=line.partition('\t')
            if not separator:name,separator,value=line.partition(':')
            if not separator:raise ValueError('Paste each specification as name TAB value or name: value')
            values.append({paste['name_key']:name.strip(),paste['value_key']:value.strip()})
        fields[paste['target_field']]=values
        if paste.get('original_field'):fields[paste['original_field']]=pasted_text
    entry=dict(entry_id=entry_id or 'manual-'+uuid.uuid4().hex,revision='1',record_type=record_type,label=label,
        fields=fields,resources=[],relations=[],provenance=dict(source_id=source_id,retrieved_at=manager.now(),
        method='clipboard' if pasted_text else 'manual',original_text=pasted_text,
        original_text_sha256=hashlib.sha256(pasted_text.encode()).hexdigest()))
    selected_contract=declared_content_contract(definition,fields)
    if selected_contract:entry['content_contract']=selected_contract
    if previous:
        entry['expected_content_sha256']=previous['content_sha256']
        entry['resources']=prior_entry.get('resources',[])
        entry['relations']=prior_entry.get('relations',[])
        if unchanged_paste and source_id==prior_entry['provenance']['source_id']:
            entry['provenance']=json.loads(canonical(prior_entry['provenance']))
        same_paste=not pasted_text or entry['provenance']['original_text_sha256']==prior_entry['provenance'].get('original_text_sha256')
        if not attachments and same_paste and fields==prior_entry['fields'] and label==prior_entry.get('label','') and source_id==prior_entry['provenance']['source_id']:
            entry=json.loads(canonical(prior_entry));entry['expected_content_sha256']=previous['content_sha256']
    for attachment in attachments or []:
        resource=local_resource(attachment['path'],attachment['role'],source_id)
        if attachment.get('expected_sha256') and attachment['expected_sha256']!=resource['sha256']:
            raise ValueError('Local attachment changed after selection')
        entry['resources'].append(resource)
    if sum(resource.get('size_bytes',0) for resource in entry['resources'])>64*1024*1024:
        raise ValueError('Manual Library attachments exceed the 64 MiB entry budget')
    validate_entry(entry,definition['library_type'],catalog)
    result=dict(schema='gxtxt.library_manual_preview.v1',library_type=definition['library_type'],entry=entry)
    if library_id:
        manager.safe_id(library_id)
        old=manager.load_registry(manager.managed_root())['libraries'].get(library_id)
        result['expected_version']=(old or {}).get('version','')
        if expected_version is not None and expected_version!=result['expected_version']:
            raise ValueError('Destination Library version changed; review selection again')
    if suggestions is not None:
        result.update(_manual_suggestions(result, suggestions, library_id, record_type))
        if len(canonical([result.get('selected_suggestions',[]),entry['relations']]))>2*1024*1024:
            raise ValueError('Selected suggestion preview exceeds 2 MiB; reduce pasted text or checked rows')
    require_scope_entry(normalized_scope,library_id,entry,result['library_type'],catalog)
    for candidate in result.get('selected_suggestions',[]):require_scope_entry(normalized_scope,library_id,candidate['entry'],result['library_type'],catalog)
    return result

def manual_candidates(record_type, text, scope=None, library_id='', source_id=''):
    """Bounded, literal user TSV; schema fields remain the sole type authority."""
    definition=schemas()['record_types'].get(record_type)
    if not definition:raise ValueError('Choose an installed Library record schema')
    if not isinstance(text,str) or len(text.encode('utf-8'))>262144:
        raise ValueError('Candidate paste exceeds 256 KiB')
    raw_lines=io.StringIO(text,newline='').readlines();lines=[];original_rows=[];last_line=0
    reader=csv.reader(io.StringIO(text,newline=''),delimiter='\t',strict=True)
    try:
        for values in reader:
            lines.append(values);original_rows.append(''.join(raw_lines[last_line:reader.line_num]));last_line=reader.line_num
            if len(lines)>21:raise ValueError('Paste at most 20 candidate rows')
    except csv.Error as error:
        raise ValueError('Malformed bounded candidate TSV') from error
    if not 2<=len(lines)<=21:raise ValueError('Paste a header and 1 to 20 candidate rows')
    header=lines[0]
    if len(set(header))!=len(header) or 'candidate_id' not in header:
        raise ValueError('Candidate TSV requires distinct column names and candidate_id')
    allowed={'candidate_id','label','source_id'}|set(definition['fields'])
    if set(header)-allowed:raise ValueError('Candidate paste contains undeclared columns')
    candidates=[];seen=set()
    for values,original_row in zip(lines[1:],original_rows[1:]):
        if len(values)!=len(header):raise ValueError('Candidate TSV row has a different column count')
        row=dict(zip(header,values));identity=row.pop('candidate_id')
        if not identity.strip() or len(identity)>512 or identity in seen:
            raise ValueError('Candidate keys must be nonempty, distinct and at most 512 characters')
        seen.add(identity);label=row.pop('label','');source=row.pop('source_id','')
        fields={}
        for key,value in row.items():
            if value=='':continue
            fields[key]=value if definition['fields'][key].get('type') in {'string','scalar'} else json.loads(value)
        candidates.append(dict(candidate_id=identity,label=label,source_id=source,fields=fields,
            original_text=original_row))
    result=dict(schema='gxtxt.library_manual_candidates.v1',candidates=candidates,original_text=text)
    normalized=normalize_scope(scope)
    if normalized:
        eligible=[row for row in candidates if scope_allows_entry(normalized,library_id,dict(record_type=record_type,provenance=dict(source_id=row['source_id'] or source_id)),definition['library_type'])]
        result.update(candidates=eligible,total=len(eligible),outside_scope_count=len(candidates)-len(eligible),scope=normalized)
    return result

def _manual_suggestions(preview, options, library_id, record_type):
    if not isinstance(options,dict) or set(options)-{'include','candidates','selected_ids','relation_type','source_id','assertion_kind','evidence','original_text','text'}:
        raise ValueError('Invalid manual suggestion options')
    if type(options.get('include',False)) is not bool:raise ValueError('Suggestion include must be boolean')
    if not options.get('include',False):return dict(selected_suggestions=[],suggestions_included=False)
    if not library_id:raise ValueError('Choose a destination Library before reviewing suggestions')
    if 'text' in options:
        if 'candidates' in options:raise ValueError('Choose candidate text or structured records, not both')
        parsed=manual_candidates(record_type,options['text'])
        options=dict(options,candidates=parsed['candidates'],original_text=parsed['original_text'])
    rows=options.get('candidates',[]);selected=options.get('selected_ids',[])
    if not isinstance(rows,list) or len(rows)>20 or not isinstance(selected,list) or len(selected)>20 or any(not isinstance(key,str) for key in selected) or len(set(selected))!=len(selected):
        raise ValueError('Review at most 20 distinct pasted candidates')
    mapping={}
    for row in rows:
        if not isinstance(row,dict) or set(row)-{'candidate_id','fields','source_id','label','original_text'}:
            raise ValueError('Invalid pasted candidate record')
        if not isinstance(row.get('fields'),dict) or any(not isinstance(row.get(name,''),str) or len(row.get(name,'').encode())>262144 for name in ('label','source_id','original_text')):
            raise ValueError('Candidate fields/original text must be bounded typed data')
        key=row.get('candidate_id')
        if not isinstance(key,str) or not key.strip() or len(key)>512 or key in mapping:
            raise ValueError('Pasted candidate keys must be nonempty and distinct')
        mapping[key]=row
    if set(selected)-set(mapping):raise ValueError('Selected candidate is absent from the reviewed paste')
    if not selected:return dict(selected_suggestions=[],suggestions_included=True)
    relation_type=options.get('relation_type','');catalog=schemas();relation=catalog['relations'].get(relation_type)
    if not relation or relation.get('manual_suggestion') is not True or record_type not in relation['from_types'] or record_type not in relation['to_types']:
        raise ValueError('Choose a declared suggestion relation compatible with this record schema')
    assertion=options.get('assertion_kind','user');source=options.get('source_id','');evidence=options.get('evidence','')
    if assertion not in {'user','source'} or not isinstance(source,str) or not source.strip() or len(source)>4096 or not isinstance(evidence,str) or not evidence.strip() or len(evidence)>16384:
        raise ValueError('Suggestions require explicit user/source attribution and literal evidence')
    original=options.get('original_text','')
    if not isinstance(original,str) or len(original.encode())>262144:raise ValueError('Candidate original paste exceeds 256 KiB')
    old=manager.load_registry(manager.managed_root())['libraries'].get(library_id)
    existing=load(manager.storage_path(manager.managed_root(),old))['entries'] if old else {}
    prepared=[];primary=preview['entry'];links=primary['relations']
    for key in selected:
        row=mapping[key];candidate_source=row.get('source_id') or source
        identity='manual-suggestion-'+hashlib.sha256(canonical([record_type,candidate_source,key])).hexdigest()[:32]
        if identity==primary['entry_id']:raise ValueError('A part cannot suggest itself')
        candidate=manual_prepare(record_type,row.get('fields'),candidate_source,label=row.get('label',''),entry_id=identity)['entry']
        candidate['provenance'].update(manual_candidate_id=key,original_candidate_text=row.get('original_text',''),original_candidates_text=original)
        prior=existing.get(identity)
        if not prior:
            prior=next((item['entry'] for item in prepared if item['entry']['fields']==candidate['fields'] and item['entry']['provenance']['source_id']==candidate_source),None)
            if prior:identity=prior['entry_id']
        if not prior:
            matches=[item for item in existing.values() if item.get('record_type')==record_type and item['fields']==candidate['fields'] and item['provenance']['source_id']==candidate_source]
            if len(matches)>1:raise ValueError('Multiple exact candidate entries exist; resolve their stable identities explicitly')
            if matches:prior=matches[0];identity=prior['entry_id']
        if identity==primary['entry_id'] or candidate['fields']==primary['fields']:
            raise ValueError('A part cannot suggest its exact original record')
        if prior:
            if prior.get('record_type')!=record_type or prior['fields']!=candidate['fields'] or prior['provenance'].get('source_id')!=candidate_source:
                raise ValueError('Existing candidate identity has different content; edit its pinned entry explicitly')
            candidate=prior
        else:
            declaration=validate_entry(candidate,preview['library_type'],catalog)
            candidate['domain_schema']=dict(provider_id=declaration['provider_id'],provider_version=declaration['provider_version'],sha256=declaration['schema_sha256'])
            candidate['content_sha256']=entry_hash(candidate)
        target=dict(kind='library_entry',library_id=library_id,entry_id=identity,record_type=record_type,
            revision=candidate['revision'],content_sha256=candidate['content_sha256'])
        edge=dict(relation_type=relation_type,target=target,source_id=source,evidence=evidence,
            assertion_kind=assertion,retrieved_at=manager.now(),original_text=original,compatibility_verified=False)
        if not any(all(old_edge.get(k)==edge[k] for k in ('relation_type','target','source_id','evidence','assertion_kind','original_text')) for old_edge in links):links.append(edge)
        prepared.append(dict(candidate_id=key,entry=candidate,status='reused' if prior else 'new'))
    validate_entry(primary,preview['library_type'],catalog)
    return dict(selected_suggestions=prepared,suggestions_included=True)

def operation(name, parameters):
    if 'scope' in parameters and parameters['scope'] is None:raise ValueError('Library scope must be a typed dictionary, not null')
    if name=='scope_describe':return scope_describe(**parameters)
    if name=='schemas':return scope_describe(**parameters)['catalog'] if parameters.get('scope') else schemas()
    if name=='connectors':
        import scientific_library_sources as sources
        return dict(schema='gxtxt.library_connectors.v1',connectors=_scoped_connectors(parameters.get('scope')))
    if name=='search':return search(**parameters)
    if name=='resolve_external_id':return resolve_external_id(**parameters)
    if name=='related':return related(**parameters)
    if name=='detail':return detail(**parameters)
    if name=='import':return import_entries(**parameters)
    if name=='import_bundle':return import_bundle(**parameters)
    if name=='local_resource':return local_resource(**parameters)
    if name=='stage':return stage(**parameters)
    if name=='manual_prepare':return manual_prepare(**parameters)
    if name=='manual_candidates':return manual_candidates(**parameters)
    if name=='manual_import':
        parameters=dict(parameters)
        library_id=parameters['library_id']
        preview=manual_prepare(**parameters)
        entries=list({row['entry']['entry_id']:row['entry'] for row in preview.get('selected_suggestions',[])}.values())+[preview['entry']]
        receipt=import_entries(library_id,preview['library_type'],entries,expected_version=preview.get('expected_version'))
        receipt['primary_entry_id']=preview['entry']['entry_id']
        receipt['selected_suggestions']=[dict(candidate_id=row['candidate_id'],entry_id=row['entry']['entry_id'],status=row['status']) for row in preview.get('selected_suggestions',[])]
        return receipt
    raise ValueError('Unknown Library domain operation')

def _index():
    root=manager.managed_root();root.mkdir(parents=True,exist_ok=True)
    registry,fingerprint=manager.registry_snapshot(root)
    catalog=schemas()
    fingerprint=hashlib.sha256(canonical([fingerprint,catalog['providers']])).hexdigest()
    connection=sqlite3.connect(root/'relations-index.sqlite',timeout=10)
    connection.row_factory=sqlite3.Row
    connection.executescript('CREATE TABLE IF NOT EXISTS state(fingerprint TEXT); CREATE TABLE IF NOT EXISTS diagnostics(library_id TEXT PRIMARY KEY,reason TEXT); CREATE TABLE IF NOT EXISTS entries(library_id TEXT,entry_id TEXT,revision TEXT,sha TEXT,record_type TEXT,label TEXT,body TEXT,PRIMARY KEY(library_id,entry_id)); CREATE TABLE IF NOT EXISTS edges(id TEXT PRIMARY KEY,from_library TEXT,from_entry TEXT,to_library TEXT,to_entry TEXT,relation_type TEXT,source_id TEXT,body TEXT); CREATE INDEX IF NOT EXISTS incoming ON edges(to_library,to_entry); CREATE INDEX IF NOT EXISTS outgoing ON edges(from_library,from_entry);')
    row=connection.execute('SELECT fingerprint FROM state').fetchone()
    if row and row[0]==fingerprint:return connection
    with connection:
        connection.execute('DELETE FROM entries');connection.execute('DELETE FROM edges');connection.execute('DELETE FROM state');connection.execute('DELETE FROM diagnostics')
        for library_id,record in sorted(registry['libraries'].items()):
            if record.get('state')!='installed' or record.get('mode','managed')!='managed':continue
            # Only declared generic record providers own this payload format.
            try:
                provider=manager.select_provider(record['library_type'],record['provider_id'])
            except ValueError:
                connection.execute('INSERT INTO diagnostics VALUES(?,?)',(library_id,'Library Type Provider is absent or disabled'))
                continue
            typed=getattr(provider['module'],'TYPED_RECORDS',False)
            if not typed and not _projection_definition(record,catalog):continue
            try:
                if typed:
                    manager._verify_managed_record(root,record,provider)
                    entries=load(manager.storage_path(root,record))['entries'].items()
                else:
                    entries=[(row['entry_id'],_project_metadata(record,row,catalog))
                        for row in manager._managed_metadata_snapshot(library_id,record)]
            except (ValueError,OSError) as error:
                connection.execute('INSERT INTO diagnostics VALUES(?,?)',(library_id,str(error)))
                continue
            for entry_id,entry in entries:
                if entry.get('tombstone'):continue
                indexed=json.loads(canonical(entry))
                for resource in indexed.get('resources',[]):resource.pop('data_base64',None)
                connection.execute('INSERT INTO entries VALUES(?,?,?,?,?,?,?)',(library_id,entry_id,entry['revision'],entry['content_sha256'],entry['record_type'],entry.get('label',entry_id),canonical(indexed).decode()))
                for ordinal,edge in enumerate(entry.get('relations',[])):
                    target=edge['target'];identity=hashlib.sha256(canonical([library_id,entry_id,entry['revision'],ordinal,edge])).hexdigest()
                    saved=dict(edge,relation_id=identity,from_reference=dict(kind='library_entry',library_id=library_id,entry_id=entry_id,record_type=entry['record_type'],revision=entry['revision'],content_sha256=entry['content_sha256']))
                    connection.execute('INSERT INTO edges VALUES(?,?,?,?,?,?,?,?)',(identity,library_id,entry_id,target.get('library_id',''),target.get('entry_id',''),edge['relation_type'],edge['source_id'],canonical(saved).decode()))
        current,_=manager.registry_snapshot(root)
        if current!=registry or schemas()['providers']!=catalog['providers']:
            raise ValueError('Library registry/schema changed while the disposable graph index was built')
        connection.execute('INSERT INTO state VALUES(?)',(fingerprint,))
    return connection

def related(reference, direction='both', relation_type='', source_id='', offset=0, limit=100, scope=None):
    if direction not in {'incoming','outgoing','both'} or type(offset) is not int or offset<0 or type(limit) is not int or not 1<=limit<=100:
        raise ValueError('Invalid bounded relation query')
    scope=normalize_scope(scope)
    read_pinned(reference,scope)
    connection=_index()
    try:
        clauses=[];args=[]
        if direction in {'incoming','both'}:clauses.append('(to_library=? AND to_entry=?)');args.extend([reference['library_id'],reference['entry_id']])
        if direction in {'outgoing','both'}:clauses.append('(from_library=? AND from_entry=?)');args.extend([reference['library_id'],reference['entry_id']])
        where='('+' OR '.join(clauses)+')'
        for key,value in (('relation_type',relation_type),('source_id',source_id)):
            if value:where+=' AND '+key+'=?';args.append(value)
        total=connection.execute('SELECT COUNT(*) FROM edges WHERE '+where,args).fetchone()[0]
        rows=[]
        for row in connection.execute('SELECT body FROM edges WHERE '+where+' ORDER BY id LIMIT ? OFFSET ?',args+[limit,offset]):
            edge=json.loads(row[0]);target=edge['target'];edge['resolution_status']='unresolved'
            if target['kind']=='library_entry':
                found=connection.execute('SELECT revision,sha FROM entries WHERE library_id=? AND entry_id=?',(target['library_id'],target['entry_id'])).fetchone()
                edge['resolution_status']='resolved' if found and found['revision']==target['revision'] and found['sha']==target['content_sha256'] else 'stale' if found else 'unresolved'
            if scope:
                other=target if edge['from_reference']['library_id']==reference['library_id'] and edge['from_reference']['entry_id']==reference['entry_id'] else edge['from_reference']
                found=connection.execute('SELECT body FROM entries WHERE library_id=? AND entry_id=?',(other.get('library_id',''),other.get('entry_id',''))).fetchone() if other.get('kind')=='library_entry' else None
                record=manager.load_registry(manager.managed_root())['libraries'].get(other.get('library_id',''),{})
                allowed=bool(found) and scope_allows_entry(scope,other['library_id'],json.loads(found['body']),record.get('library_type'))
                if other.get('kind')=='canonical_dataset' and not scope.get('library_ids') and not scope.get('source_ids'):
                    # Domain-declared target type is presentation context only;
                    # actual Session/revision/SHA admission stays DatasetViewer.
                    allowed=other.get('record_type') in _scope_record_types(scope,schemas())
                edge['scope_status']='inside_scope' if allowed else 'outside_scope'
                if not allowed:edge['scope_reason']='Linked assertion is retained; its target is outside or cannot establish this Library scope'
            edge['why_related']=edge['evidence'];rows.append(edge)
        return dict(schema='gxtxt.library_relations_page.v1',records=rows,total=total,offset=offset,limit=limit,
            unavailable_libraries=[dict(row) for row in connection.execute('SELECT * FROM diagnostics ORDER BY library_id')])
    finally:connection.close()

def search(query='', record_type='', offset=0, limit=100, scope=None):
    if not isinstance(query,str) or len(query)>4096 or type(offset) is not int or offset<0 or type(limit) is not int or not 1<=limit<=100:
        raise ValueError('Invalid bounded cross-Library search')
    connection=_index()
    try:
        where="(?='' OR record_type=?) AND instr(lower(body),lower(?))>0"
        args=[record_type,record_type,query]
        clauses,extra=_scope_sql(scope)
        if clauses:where+=' AND '+' AND '.join(clauses);args.extend(extra)
        total=connection.execute('SELECT COUNT(*) FROM entries WHERE '+where,args).fetchone()[0]
        rows=[dict(row) for row in connection.execute('SELECT library_id,entry_id,revision,sha AS content_sha256,record_type,label FROM entries WHERE '+where+' ORDER BY library_id,entry_id LIMIT ? OFFSET ?',args+[limit,offset])]
        return dict(schema='gxtxt.library_search_page.v1',records=rows,total=total,offset=offset,limit=limit,
            unavailable_libraries=[dict(row) for row in connection.execute('SELECT * FROM diagnostics ORDER BY library_id')])
    finally:connection.close()

def resolve_external_id(source_id, external_id, record_type='', offset=0, limit=100, scope=None):
    if any(not isinstance(value,str) or not value or len(value)>4096 for value in (source_id,external_id)) or type(offset) is not int or offset<0 or type(limit) is not int or not 1<=limit<=100:
        raise ValueError('Invalid bounded qualified external identity query')
    connection=_index()
    try:
        where="json_extract(body,'$.provenance.source_id')=? AND json_extract(body,'$.provenance.external_id')=? AND (?='' OR record_type=?)"
        args=[source_id,external_id,record_type,record_type]
        clauses,extra=_scope_sql(scope)
        if clauses:where+=' AND '+' AND '.join(clauses);args.extend(extra)
        total=connection.execute('SELECT COUNT(*) FROM entries WHERE '+where,args).fetchone()[0]
        rows=[dict(row) for row in connection.execute('SELECT library_id,entry_id,revision,sha AS content_sha256,record_type,label FROM entries WHERE '+where+' ORDER BY library_id,entry_id LIMIT ? OFFSET ?',args+[limit,offset])]
        return dict(schema='gxtxt.library_external_identity_candidates.v1',records=rows,total=total,offset=offset,limit=limit)
    finally:connection.close()
