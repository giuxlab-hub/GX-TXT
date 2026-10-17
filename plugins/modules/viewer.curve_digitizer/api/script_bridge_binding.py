"""Public Digitizer lineage and covariance consumers for both Script languages."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

_OPS = {
    'uncertainty_report': ('uncertaintyReport', ['document_id', 'document_sha256']),
    'publication_uncertainty': ('publicationUncertainty', ['dataset_id']),
    'publish_covariance': ('publishCovariance', ['dataset_id', 'output_dataset_id', 'axis']),
}
REGISTRATION = {
    'api_id': 'CURVE_DIGITIZER_COMPANION_API_v1', 'api_version': 1,
    'provider_kind': 'module', 'provider_id': 'viewer.curve_digitizer',
    'documentation_ref': 'docs/api/DIGITIZATION_UNCERTAINTY_v1.md',
    'operations': {name: {'name': name, 'summary': 'Digitizer ' + name,
        'arguments': [{'name': arg, 'kind': 'text', 'required': True} for arg in args],
        'result_contract': 'Public CORE interpretation, exact source binding or canonical covariance publication'}
        for name, (_, args) in _OPS.items()},
}


def invoke(host, operation, args):
    if operation not in _OPS or len(args) != len(_OPS[operation][1]):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Invalid Digitizer operation arguments')
    host.call('::GX::modulePublicApiActivate', 'viewer.curve_digitizer', 'CURVE_DIGITIZER_COMPANION_API_v1')
    raw = host.call('::GX::CurveDigitizerCompanion::' + _OPS[operation][0], *args)
    text = lambda value: str(host.tcl.call('format', '%s%s', value, ''))
    if operation == 'uncertainty_report':
        return text(raw)
    if operation == 'publish_covariance':
        result = host.as_dict(raw)
        return {key: int(value) if key in ('variable_count', 'row_count') else text(value) for key, value in result.items()}
    if not text(raw):
        return {'available': False}
    capture = host.as_dict(raw)
    # Reuse the CORE-owned typed adapter; no consumer-private statistical labels.
    meaning = host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1']._digitization_result(host, capture['meaning'])
    binding = host.as_dict(capture['binding'])
    return {'available': True, 'meaning': meaning, 'dataset_id': text(binding['dataset_id']),
            'payload_sha256': text(binding['payload_sha256']), 'point_count': int(binding['point_count']),
            'binding_utf8': text(capture['binding']),
            'source_identity': {key: text(value) for key, value in host.as_dict(capture['source_identity']).items()}}
