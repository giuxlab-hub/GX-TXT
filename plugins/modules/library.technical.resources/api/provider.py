# SPDX-License-Identifier: GPL-3.0-or-later
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'core'/'python'))
from scientific_library_records import *
import scientific_library_records as records
import scientific_library_sources as sources
LIBRARY_TYPE='technical.resources'
TYPED_RECORDS=True
LIBRARY_CAPABILITIES=dict(CAPABILITIES,modes=['managed','remote'],authentication_required=True)
LIBRARY_AUTHENTICATION={'api_version':1,'credential_kind':'opaque_utf8','runtime':'inline'}
REGISTRATION_SCHEMA={'remote':{'required':['connector'],'optional':[]}}
library_authentication_scope=sources.authentication_scope
library_status=sources.status
def validate_registration(mode,configuration):
    if mode!='remote' or configuration['connector'] not in sources.connectors() or LIBRARY_TYPE not in sources.connectors()[configuration['connector']]['library_types']:
        raise ValueError('Choose a compatible installed Library Source Connector')
def list_entries(record,parameters,framework):
    if record.get('mode')=='remote':raise ValueError('Enter an exact query; remote bulk listing is not supported')
    return records.list_entries(record,parameters,framework)
def search_entries(record,parameters,framework):
    return (sources if record.get('mode')=='remote' else records).search_entries(record,parameters,framework)
def read_entry(record,parameters,framework):
    return (sources if record.get('mode')=='remote' else records).read_entry(record,parameters,framework)
def entry_info(record,parameters,framework):
    return (sources if record.get('mode')=='remote' else records).entry_info(record,parameters,framework)
