"""Native public XML documents within the existing Python/Octave Bridge host."""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
from gxtxt_script_bridge_server import BridgeError
FIELDS={'create':['root_name'],'parse':['xml_text'],'parse_file':['authorized_path'],'root':['document'],'describe':['document','node'],'append':['document','parent','name','text'],'insert':['document','before','name','text'],'text':['document','node','value'],'add_text':['document','parent','text'],'attribute':['document','node','name','value'],'remove':['document','node'],'move':['document','node','parent'],'query':['document','node','tag'],'serialize':['document','indent'],'write':['document','destination'],'release':['document']}
# Metadata describes the existing public Tcl/native contract. It does not
# change native dispatch, accept arbitrary commands or grant new file access.
OPTIONAL_FIELDS = {
    'append': {'text'}, 'insert': {'text'}, 'text': {'value'},
    'attribute': {'value'}, 'serialize': {'indent'},
}
ARGUMENT_KINDS = {
    'root_name': 'unqualified XML name string; no namespace prefix',
    'xml_text': 'UTF-8 XML text string; at most 4 MiB',
    'authorized_path': 'input path confined to this managed Bridge Session',
    'document': 'opaque XML document handle owned by this Bridge interpreter',
    'node': 'opaque node handle from the supplied document',
    'parent': 'opaque element node handle from the supplied document',
    'before': 'opaque node handle with an element parent in the supplied document',
    'name': 'XML qualified name string; namespace prefix must already be declared',
    'text': 'UTF-8 text string',
    'value': 'UTF-8 string; meaning depends on the text/attribute operation',
    'tag': 'local element name string or *',
    'indent': 'optional 0/1 serialization indentation; default 0',
    'destination': 'create-only output path confined to this managed Job output directory',
}
RESULTS = {
    'create': 'opaque document handle string',
    'parse': 'opaque document handle string',
    'parse_file': 'opaque document handle string',
    'root': 'opaque root node handle string',
    'describe': 'struct: id, name, namespace, prefix, text strings; children list/cell of node handles; attributes string map/struct; node_type integer',
    'append': 'opaque new child node handle string',
    'insert': 'opaque new preceding-sibling node handle string',
    'text': 'UTF-8 content string when value omitted; empty string after replacement',
    'add_text': 'opaque retained text node handle string; adjacent text may merge',
    'attribute': 'UTF-8 attribute value string when value omitted; empty string after write/removal/namespace declaration',
    'remove': 'empty string; removed subtree handles invalidated',
    'move': 'empty string; unmerged nodes retain their handle; a merged source-text handle becomes stale',
    'query': 'ordered list/cell of matching element node handles in the supplied node subtree, including that node when it matches',
    'serialize': 'UTF-8 XML string; at most 8 MiB',
    'write': 'existing create-only File Publication receipt; files map normalized to language structs',
    'release': 'empty string; all document/node handles invalidated',
}
CONTEXT_NOTES = {
    'append': 'Omitted text creates the element without a new text child.',
    'insert': 'The before node must have an element parent; omitted text creates no text child.',
    'text': 'Omit value to read; supplying value replaces content and invalidates old child handles.',
    'attribute': 'Omit value to read an ordinary attribute. xmlns or xmlns:prefix declarations require a URI value. Value --remove removes an ordinary attribute.',
    'serialize': 'The public documented indent values are 0/1; the existing native owner treats exact 1 as indentation.',
    'parse_file': 'Reads only within the managed Session; no arbitrary host path admission.',
    'write': 'Writes only within the managed Job output directory through existing atomic File Publication; no Dataset publication is implied.',
    'move': 'Same-document element and unmerged text moves preserve identity. Adjacent text merges retain the destination text handle and invalidate the consumed source-text handle; inspect destination children to obtain the retained handle. Cycle/depth rejection preserves the original tree.',
}
REGISTRATION = {
    'api_id': 'XML_DOCUMENT_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'xml_document',
    'documentation_ref': 'docs/api/XML_DOCUMENT_API_v1.md',
    'operations': {
        name: {
            'name': name, 'summary': 'Native XML document '+name,
            'arguments': [
                {'name': field, 'kind': ARGUMENT_KINDS[field],
                 'required': field not in OPTIONAL_FIELDS.get(name, ())}
                for field in fields
            ],
            'argument_convention': ', '.join(
                field+' (optional)' if field in OPTIONAL_FIELDS.get(name, ()) else field
                for field in fields
            ),
            'result_contract': RESULTS[name],
            'context': CONTEXT_NOTES.get(name, 'Opaque handles remain interpreter/document scoped; existing native validation applies.'),
        }
        for name, fields in FIELDS.items()
    },
}
def invoke(host,operation,args):
    if operation not in FIELDS:raise BridgeError('GXTXT:XML:Operation','Unknown XML operation')
    args=list(args)
    if operation in {'write','parse_file'}:
        pos=1 if operation=='write' else 0
        root=Path(host.config.get('runtime','output_dir')).resolve() if operation=='write' else Path(host.session).resolve()
        path=Path(args[pos]);path=path if path.is_absolute() else root/path
        resolved=path.resolve()
        if not resolved.is_relative_to(root) or any(p.is_symlink() for p in [path,*path.parents] if p!=root.parent):
            raise BridgeError('GXTXT:XML:Authorization','XML file operation escaped the authorized run/Session root')
        args[pos]=str(resolved)
    result=host.call('::GX::xmlDocument',operation,*args)
    if operation=='describe':
        result=host.as_dict(result);result['children']=host.as_list(result['children']);result['attributes']=host.as_dict(result['attributes']);result['node_type']=int(result['node_type']);return result
    if operation=='query':return host.as_list(result)
    if operation=='write':
        receipt=host.as_dict(result);receipt['files']={str(k):host.as_dict(v) for k,v in host.as_dict(receipt['files']).items()};return receipt
    return str(result)
