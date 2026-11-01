"""PubChem PUG REST/View source adapter, independent of Library/Dataset storage."""
# SPDX-License-Identifier: GPL-3.0-or-later
import base64
import hashlib
import json
from pathlib import Path
import re
import tempfile
import urllib.parse
from scientific_library_manager import now
from scientific_library_records import canonical
from scientific_library_sources import request
CONNECTOR_ID='source.pubchem'
HOST='pubchem.ncbi.nlm.nih.gov'
BASE='https://'+HOST+'/rest/'

def get(path):return request(BASE+path,allowed_hosts={HOST},interval=.3)
def data(path):return json.loads(get(path))
def stable(*parts):return 'pubchem-'+hashlib.sha256(canonical(parts)).hexdigest()[:24]
def entry(record_type,external_id,fields,label=''):
    return dict(entry_id=stable(record_type,external_id),revision='1',record_type=record_type,label=label or external_id,
        fields=fields,resources=[],relations=[],provenance=dict(source_id=CONNECTOR_ID,external_id=external_id,
        retrieved_at=now(),normalization_version='1',source_url=('https://pubmed.ncbi.nlm.nih.gov/'+external_id[5:]+'/' if external_id.startswith('pmid:') else 'https://pubchem.ncbi.nlm.nih.gov/compound/'+external_id.split(':')[0])))
def cid(value):
    if not isinstance(value,str) or not re.fullmatch(r'[1-9][0-9]{0,11}',value):raise ValueError('Select an exact positive PubChem CID')
    return value

def resolve(query):
    if query.isdecimal():return [int(cid(query))]
    namespace,separator,value=query.partition(':')
    if not separator:namespace,value='name',query
    if namespace not in {'name','smiles','inchikey','inchi'} or not value or len(value)>500:
        raise ValueError('PubChem query requires name, CID, smiles:, inchikey: or inchi:')
    if namespace=='inchi':
        raw=request(BASE+'pug/compound/inchi/cids/JSON',allowed_hosts={HOST},data=urllib.parse.urlencode({'inchi':value}).encode(),headers={'Content-Type':'application/x-www-form-urlencoded'})
        result=json.loads(raw)
    else:result=data('pug/compound/'+namespace+'/'+urllib.parse.quote(value,safe='')+'/cids/JSON')
    values=result.get('IdentifierList',{}).get('CID')
    if not isinstance(values,list) or not all(type(x) is int and x>0 for x in values) or len(values)>50:
        raise ValueError('PubChem identity list is absent, malformed or exceeds 50; narrow query')
    return values

def properties(cids):
    result=data('pug/compound/cid/'+','.join(map(str,cids))+'/property/MolecularFormula,MolecularWeight,InChI,InChIKey,IUPACName/JSON')
    rows=result.get('PropertyTable',{}).get('Properties')
    if not isinstance(rows,list) or {row.get('CID') for row in rows}!={int(x) for x in cids}:
        raise ValueError('PubChem compound property identity mismatch')
    return rows

def search(query,limit=50):
    rows=properties(resolve(query)[:min(limit,50)])
    return [dict(entry_id=str(row['CID']),metadata=dict(label=row.get('IUPACName',str(row['CID'])),**row),
        provenance=dict(source_id=CONNECTOR_ID)) for row in rows]

def _sections(value):
    for section in value.get('Section',[]):
        if not isinstance(section,dict):raise ValueError('PubChem View section schema changed')
        yield section
        yield from _sections(section)

def normalize(properties_record,view_record=None,pubmed=None,structures=None):
    if not isinstance(properties_record,dict) or type(properties_record.get('CID')) is not int:
        raise ValueError('PubChem property record has no CID')
    identity=cid(str(properties_record['CID']))
    identifiers={'pubchem.cid':identity}
    for name in ('InChI','InChIKey'):
        if properties_record.get(name):identifiers['pubchem.'+name]=properties_record[name]
    compound=entry('chemistry.compound',identity,dict(identifiers=identifiers,properties=properties_record),properties_record.get('IUPACName',identity))
    compound['provenance']['original_record_sha256']=hashlib.sha256(canonical(properties_record)).hexdigest()
    rows=[dict(library_type='chemistry.records',entry=compound)]
    def related(item,typ,evidence,library_type='chemistry.records'):
        rows.append(dict(library_type='molecular.structures' if item['record_type']=='chemistry.structure' else library_type,entry=item))
        compound['relations'].append(dict(relation_type=typ,target=dict(kind='external_source_entity',source_id=CONNECTOR_ID,
            external_id=item['provenance']['external_id'],record_type=item['record_type']),source_id=CONNECTOR_ID,
            evidence=evidence,assertion_kind='source',retrieved_at=now()))
    for structure in structures or []:
        item=entry('chemistry.structure',identity+':'+structure['identity'],dict(identifiers=identifiers,geometry_origin=structure['origin'],
            coordinate_unit='angstrom',dimensionality=structure['dimensionality'],conformer_id=structure.get('conformer_id',''),
            validated_atoms=structure['atoms'],validated_bonds=structure['bonds']),identity+' '+structure['identity'])
        item['resources']=[structure['resource']];item['content_contract']='molecular.structure'
        related(item,'chemistry.has_structure','PubChem source-preserved '+structure['origin'])
    if view_record:
        record=view_record.get('Record')
        if not isinstance(record,dict) or record.get('RecordNumber')!=int(identity):raise ValueError('PubChem View record identity mismatch')
        references={ref.get('ReferenceNumber'):ref for ref in record.get('Reference',[])}
        ordinal=0
        for section in _sections(record):
            heading=section.get('TOCHeading','')
            if heading=='GHS Classification':
                for info in section.get('Information',[]):
                    ordinal+=1;reference=references.get(info.get('ReferenceNumber'),{})
                    contributor=reference.get('SourceName',info.get('Name','PubChem contributor not specified'))
                    item=entry('chemistry.safety_claim',identity+':ghs:'+str(ordinal),dict(contributor=contributor,
                        claims=[info],source_record=dict(information=info,reference=reference),jurisdiction='not_provided',source_revision=str(record.get('RecordVersion','not_provided'))),contributor+' GHS claim')
                    related(item,'chemistry.has_safety_claim','PUG View source-attributed GHS information; no authoritative SDS claim')
            elif heading in {'Spectral Information','IR Spectra','NMR Spectra','Mass Spectrometry','Raman Spectra','UV Spectra'}:
                item=entry('chemistry.spectrum_reference',identity+':spectra:'+stable(heading,section),dict(heading=heading,source_record=section),heading+' (external source information)')
                related(item,'chemistry.has_spectrum_reference','Actual PUG View spectral section; numerical trace not implied')
    for value in (pubmed or [])[:50]:
        if not str(value).isdecimal():raise ValueError('PubChem publication reference is not a PubMed identifier')
        item=entry('scientific.publication','pmid:'+str(value),dict(identifiers={'pubmed.pmid':str(value)},url='https://pubmed.ncbi.nlm.nih.gov/'+str(value)+'/'),'PubMed '+str(value))
        item['content_contract']='scientific.publication'
        related(item,'chemistry.has_publication','PUG REST PubMedID cross-reference; article metadata/full text not supplied','scientific.publications')
    return dict(schema='gxtxt.library_source_bundle.v1',source_id=CONNECTOR_ID,primary_entry_id=compound['entry_id'],entries=rows,
        suggestions=[],include_alternatives_default=False,session_datasets_created=0)

def read(value,options=None):
    identity=cid(value);options=options or {};warnings=[];structures=[]
    props=properties([identity])[0]
    # Existing molecule_io owns parsing, geometry/atom/bond validation.
    if options.get('structures',True):
        import molecule_io
        for dimension in ('3d','2d'):
            try:raw=get('pug/compound/cid/'+identity+'/SDF?record_type='+dimension)
            except ValueError as error:
                if '404' in str(error):warnings.append(dimension+' structure unavailable');continue
                raise
            with tempfile.TemporaryDirectory(prefix='gxtxt-pubchem-structure-') as temporary:
                path=Path(temporary)/'structure.sdf';path.write_bytes(raw)
                frames=molecule_io.read_sdf(path)
            match=re.search(rb'>\s*<PUBCHEM_CONFORMER_ID>\s*\r?\n([^\r\n]+)',raw)
            conformer=match[1].decode('ascii') if match else ''
            structures.append(dict(identity=conformer or dimension,conformer_id=conformer,
                origin='computed_3d' if dimension=='3d' else 'source_2d',dimensionality=dimension,
                atoms=len(frames[0][1]),bonds=len(frames[0][2]),resource=dict(role='molecular_structure',original_filename='pubchem-'+identity+'-'+dimension+'.sdf',
                    media_type='chemical/x-mdl-sdfile',availability='local',source_id=CONNECTOR_ID,
                    sha256=hashlib.sha256(raw).hexdigest(),data_base64=base64.b64encode(raw).decode(),size_bytes=len(raw))))
            break
    view=None;pubmed=[]
    for kind in ('view','pubmed'):
        try:
            if kind=='view':view=data('pug_view/data/compound/'+identity+'/JSON')
            else:
                result=data('pug/compound/cid/'+identity+'/xrefs/PubMedID/JSON')
                pubmed=result.get('InformationList',{}).get('Information',[{}])[0].get('PubMedID',[])
        except ValueError as error:
            if '404' in str(error):warnings.append(kind+' unavailable')
            else:raise
    result=normalize(props,view,pubmed,structures);result['warnings']=warnings
    return result
