# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded scientific *descriptions*, not numeric Dataset validation or ingestion.

Only legacy numeric_source 1-D records delegate the unchanged spectrum validator.
Other branches inspect inert provider-declared metadata; they never read a RAW,
resolve a Session/Registry identity, convert units or claim numeric correctness.
"""
import importlib.util
import json
from pathlib import Path
import re

TYPES = {'scientific.scalar_measurement','scientific.complex_spectrum',
         'scientific.multidimensional_spectrum','scientific.spatial_measurement',
         'scientific.frame_sequence','scientific.temporal_trace','scientific.measurement_array'}
IDENTIFIER = re.compile(r'[A-Za-z][A-Za-z0-9_.-]{0,255}')
CONTRACT = re.compile(r'[A-Za-z0-9_][A-Za-z0-9_.:+/-]{0,127}')
SHA = re.compile(r'[a-f0-9]{64}')

def _text(value, label, maximum=4096, empty=False):
    if not isinstance(value,str) or len(value)>maximum or '\x00' in value or (not empty and not value):
        raise ValueError('Invalid scientific description '+label)
    return value

def _id(value,label):
    if not isinstance(value,str) or not IDENTIFIER.fullmatch(value):raise ValueError('Invalid description '+label)
    return value

def _ids(value,label):
    if not isinstance(value,list) or len(value)>256 or any(not isinstance(v,str) for v in value):raise ValueError('Invalid description '+label)
    for v in value:_id(v,label)
    if len(set(value))!=len(value):raise ValueError('Duplicate description '+label)
    return value

def _array(value,label):
    if not isinstance(value,list) or len(value)>256:raise ValueError('Description '+label+' must be a bounded array')
    return value

def _sha(value,label):
    if not isinstance(value,str) or not SHA.fullmatch(value):raise ValueError('Description requires exact '+label+' SHA256')

def _links(entry,model,own_only=False):
    for relation in entry.get('relations',[]):
        if own_only and relation.get('relation_type') not in {'scientific.describes_dataset','scientific.related_measurement'}:continue
        target=relation.get('target',{})
        if relation.get('relation_type')=='scientific.describes_dataset':
            if target.get('kind')!='canonical_dataset' or target.get('record_type')!=entry['record_type']:
                raise ValueError('Describes Dataset requires its own scientific record type and canonical anchor')
        if target.get('kind')=='canonical_dataset':
            _sha(target.get('revision'),'Dataset revision');_sha(target.get('sha256'),'Dataset payload')
            if target['sha256']!=target['revision']:raise ValueError('Dataset SHA and revision contradict each other')
            _text(target.get('session_id'),'Session identity');_text(target.get('dataset_id'),'Dataset identity',512)
            contract=target.get('contract')
            if not isinstance(contract,str) or not CONTRACT.fullmatch(contract):raise ValueError('Dataset link requires its actual contract')
            if relation.get('relation_type')=='scientific.describes_dataset' and model.get('dataset_contracts') and contract not in model['dataset_contracts']:
                raise ValueError('Dataset link contract differs from this explicit description')
        elif target.get('kind')=='library_entry':_sha(target.get('content_sha256'),'Library target content')

def _model(entry):
    model=entry['fields'].get('measurement')
    if not isinstance(model,dict) or model.get('schema')!='gxtxt.library_measurement_description.v1':
        raise ValueError('A versioned scientific measurement description is required')
    allowed={'schema','source_format','source_sha256','source_resources','modality','storage_kind',
             'dataset_contracts','dimensions','variables','components','sequence_dimension_ids',
             'observed_metadata','binary_resource'}
    if set(model)-allowed:raise ValueError('Undeclared measurement description fields')
    try:raw=json.dumps(model,ensure_ascii=False,allow_nan=False,separators=(',',':')).encode('utf-8')
    except (ValueError,TypeError,OverflowError):raise ValueError('Measurement description must be finite JSON') from None
    if len(raw)>131072:raise ValueError('Measurement description exceeds128KiB')
    _text(model.get('source_format'),'observed source format',256)
    _text(model.get('modality'),'observed modality',512,empty=True)
    if 'source_sha256' in model:_sha(model['source_sha256'],'original source')
    sources=_array(model.get('source_resources',[]),'source resources')
    if 'source_sha256' not in model and not sources:raise ValueError('Description requires an exact original source identity/hash')
    for source in sources:
        if not isinstance(source,dict) or set(source)-{'source_id','sha256','role'}:raise ValueError('Invalid source resource description')
        _text(source.get('source_id'),'source identity');_sha(source.get('sha256'),'source resource');_text(source.get('role'),'source role',128)
    contracts=_array(model.get('dataset_contracts',[]),'Dataset contracts')
    if any(not isinstance(c,str) or not CONTRACT.fullmatch(c) for c in contracts) or len(set(contracts))!=len(contracts):
        raise ValueError('Description preserves literal distinct Dataset contract IDs')
    dimensions={}
    for item in _array(model.get('dimensions',[]),'dimensions'):
        if not isinstance(item,dict) or set(item)-{'dimension_id','size','quantity','unit','unit_status','label'}:
            raise ValueError('Invalid dimension description')
        name=_id(item.get('dimension_id'),'dimension identity');size=item.get('size')
        if name in dimensions or type(size) is not int or size<0:raise ValueError('Invalid duplicate/dimension size')
        for key in ('quantity','unit','label'):
            if key in item:_text(item[key],'dimension '+key,512,empty=True)
        if 'unit_status' in item and (item['unit_status'] not in {'declared','unknown'} or (item['unit_status']=='unknown' and item.get('unit'))):raise ValueError('Unknown dimension unit must remain unknown')
        dimensions[name]=size
    variables={}
    allowed_variables={'variable_id','dtype','rank','shape','dimension_ids','coordinate_variable_ids',
        'coordinate_role','component_ids','group_id','axis_kind','axis_origin','axis_step','axis_count',
        'unit','unit_status','quantity','semantic_role','source_header','display_label'}
    for item in _array(model.get('variables',[]),'variables'):
        if not isinstance(item,dict) or set(item)-allowed_variables:raise ValueError('Invalid variable description')
        identity=_id(item.get('variable_id'),'variable identity')
        if identity in variables:raise ValueError('Duplicate variable identity')
        _text(item.get('dtype'),'observed dtype',128)
        rank=item.get('rank');shape=item.get('shape');ids=_ids(item.get('dimension_ids'),'variable dimensions')
        if type(rank) is not int or not 0<=rank<=256 or not isinstance(shape,list) or len(shape)!=rank or len(ids)!=rank:
            raise ValueError('Variable description must preserve exact rank/shape/dimension count')
        if any(type(n) is not int or n<0 for n in shape) or any(d not in dimensions or dimensions[d]!=n for d,n in zip(ids,shape)):
            raise ValueError('Variable description shape disagrees with its dimension identities')
        if item.get('coordinate_role') not in {'data','coordinate','auxiliary'}:raise ValueError('Explicit variable coordinate role required')
        _text(item.get('unit'),'observed unit',256,empty=True)
        if item.get('unit_status') not in {'declared','unknown'} or (item['unit_status']=='unknown' and item['unit']) or (item['unit_status']=='declared' and not item['unit']):
            raise ValueError('Unknown unit must remain explicitly unknown, not guessed')
        if 'axis_kind' in item and item['axis_kind'] not in {'explicit','uniform','none'}:raise ValueError('Invalid declared axis kind')
        if item.get('axis_kind')=='uniform':
            if any(type(item.get(k)) not in (int,float) for k in ('axis_origin','axis_step')) or item['axis_step']==0 or type(item.get('axis_count')) is not int or item['axis_count']<0:
                raise ValueError('Uniform axis description requires finite numeric origin/nonzero step and integer count')
            if rank!=1 or shape[0]!=item['axis_count']:raise ValueError('Uniform axis count contradicts its shape')
        _ids(item.get('coordinate_variable_ids',[]),'coordinate relationships');_ids(item.get('component_ids',[]),'component relationships')
        variables[identity]=item
    for item in variables.values():
        for key in ('coordinate_variable_ids','component_ids'):
            if any(ref not in variables for ref in item.get(key,[])):raise ValueError('Description refers to an absent stable Variable ID')
        for ref in item.get('coordinate_variable_ids',[]):
            if variables[ref]['coordinate_role']!='coordinate':raise ValueError('Coordinate relationship targets a non-coordinate description')
    component_ids=set()
    for component in _array(model.get('components',[]),'component groups'):
        if not isinstance(component,dict) or set(component)-{'component_id','representation','variable_ids','roles'}:
            raise ValueError('Invalid component group description')
        identity=_id(component.get('component_id'),'component group')
        refs=_ids(component.get('variable_ids'),'component Variables')
        if identity in component_ids or not refs or any(ref not in variables for ref in refs):raise ValueError('Invalid duplicate/component group membership')
        component_ids.add(identity);_text(component.get('representation'),'observed component representation',128)
        if 'roles' in component:
            if not isinstance(component['roles'],list) or len(component['roles'])!=len(refs):raise ValueError('Component role/order count mismatch')
            for role in component['roles']:_text(role,'component role',128)
    sequence=_ids(model.get('sequence_dimension_ids',[]),'sequence dimensions')
    if any(ref not in dimensions for ref in sequence):raise ValueError('Sequence axis is absent from declared dimensions')
    kind=model.get('storage_kind')
    if kind not in {'numeric_variables','opaque_resource'}:raise ValueError('Explicit observed storage kind required')
    if kind=='numeric_variables' and not variables:raise ValueError('Numeric description requires explicit Variable metadata')
    if kind=='opaque_resource':
        binary=model.get('binary_resource')
        if variables or not isinstance(binary,dict) or set(binary)-{'sha256','media_type','storage_kind'}:raise ValueError('Opaque content must not fabricate numeric Variables')
        _sha(binary.get('sha256'),'binary resource');_text(binary.get('media_type'),'observed media type',256);_text(binary.get('storage_kind'),'binary storage kind',128)
    if 'observed_metadata' in model and not isinstance(model['observed_metadata'],dict):raise ValueError('Observed metadata is an inert typed object')
    _links(entry,model)
    return model,list(v for v in variables.values() if v['coordinate_role']=='data')

def validate_entry(entry,framework):
    fields=entry['fields'];record_type=entry['record_type'];mode=fields.get('representation','numeric_source' if record_type=='scientific.spectrum' else 'description_only')
    if record_type=='scientific.spectrum' and mode=='numeric_source':
        if 'measurement' in fields:raise ValueError('Numeric source uses actual parser validation; clear description-only measurement metadata')
        if fields.get('format') not in {'csv','jcamp'} or not isinstance(fields.get('parser_options'),dict):raise ValueError('Numeric Spectrum requires original format and parser options')
        path=Path(__file__).with_name('spectrum_validation.py')
        spec=importlib.util.spec_from_file_location('gxtxt_existing_numeric_spectrum_validation',path)
        delegate=importlib.util.module_from_spec(spec);spec.loader.exec_module(delegate)
        delegate.validate_entry(entry,framework)
        _links(entry,{},own_only=True)
        return
    if (record_type!='scientific.spectrum' and record_type not in TYPES) or mode!='description_only':raise ValueError('Unknown scientific representation')
    import scientific_library_graph as graph
    if not callable(getattr(graph,'declared_content_contract',None)):
        raise ValueError('Description-only Library records require CORE literal_content_contract_selector_v1 (DEV111-P033 or later)')
    if entry.get('content_contract'):raise ValueError('Description-only record is not a validated canonical scientific payload')
    if 'format' in fields or 'parser_options' in fields or 'sample_count' in fields:raise ValueError('Description-only record cannot claim numeric-source parser validation')
    model,data=_model(entry)
    if record_type=='scientific.spectrum' and (not data or any(v['rank']!=1 for v in data)):
        raise ValueError('One-dimensional spectrum description must retain rank-one signal Variables')
    if record_type=='scientific.scalar_measurement' and (not data or any(v['rank']!=0 for v in data)):
        raise ValueError('Scalar description requires actual rank-zero scalar metadata')
    if record_type=='scientific.complex_spectrum' and not model.get('components'):
        raise ValueError('Complex description requires explicit observed component membership/representation')
    if record_type in {'scientific.multidimensional_spectrum','scientific.spatial_measurement'} and model['storage_kind']=='numeric_variables' and not any(v['rank']>=2 for v in data):
        raise ValueError('Multidimensional/spatial numeric description must retain ranked shape')
    if record_type=='scientific.frame_sequence' and (not data or not model.get('sequence_dimension_ids')):
        raise ValueError('Frame/sequence description requires explicit sequence dimension identity')
    if record_type=='scientific.temporal_trace' and (not data or not any(v.get('semantic_role')=='time' for v in model.get('variables',[]) if v['coordinate_role']=='coordinate')):
        raise ValueError('Temporal description requires its explicit observed time coordinate')
