"""Producer-scoped Dataset Group operations through the common CORE owner."""
# SPDX-License-Identifier: GPL-3.0-or-later
import json
import math
from gxtxt_script_bridge_server import BridgeError, NumericArray

REGISTRATION = {
    "api_id": "DATASET_GROUP_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "dataset_group",
    "documentation_ref": "docs/api/DATASET_GROUP_API_v1.md",
    "operations": {
        "review": {"name": "review", "summary": "Review 0..64 actual owned outputs and current Session",
                   "arguments": [{"name": "dataset_ids", "kind": "Dataset ID list", "required": True}],
                   "argument_convention": "Dataset ID list", "result_contract": "producer review with opaque full revision strings"},
        "create": {"name": "create", "summary": "Explicitly group reviewed producer-owned outputs without changing payloads",
                   "arguments": [{"name": "definition", "kind": "Group declaration", "required": True},
                                 {"name": "review", "kind": "producer review", "required": True}],
                   "argument_convention": "definition, review", "result_contract": "canonical Dataset Group descriptor"},
        "get": {"name": "get", "summary": "Inspect an existing Group and actual member integrity",
                "arguments": [{"name": "group_id", "kind": "Group ID", "required": True}],
                "argument_convention": "Group ID", "result_contract": "Group descriptor and integrity issues"},
        "list": {"name": "list", "summary": "List current Session Dataset Groups",
                 "arguments": [], "argument_convention": "no arguments", "result_contract": "Group descriptor list"},
    },
}


def bounded(value):
    numeric_bytes = 0
    def numeric_descriptor(item):
        nonlocal numeric_bytes
        if not isinstance(item, NumericArray):
            raise TypeError('Unsupported Dataset Group control value')
        shape = list(item.shape)
        if not 1 <= len(shape) <= 16 or any(type(n) is not int or n < 0 for n in shape) or math.prod(shape) != len(item.values):
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Numeric publication shape is invalid')
        numeric_bytes += int(getattr(item.values, 'nbytes', len(item.values) * 8))
        if numeric_bytes > 67108864:
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Batch numeric payload exceeds 64 MiB')
        # Count the bounded control descriptor; the existing Bridge/Tcl adapter
        # retains the actual shaped numeric values and exact integer dtype.
        return {'numeric_shape': shape, 'dtype': str(item.dtype), 'count': len(item.values)}
    # This serialization measures control bytes only. The canonical writer,
    # not this adapter, owns dtype/missing-value/NaN/Inf semantics.
    if len(json.dumps(value, ensure_ascii=False, allow_nan=True, default=numeric_descriptor).encode('utf-8')) > 1048576:
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Dataset Group control value exceeds 1 MiB; full revisions are never truncated')
    return value


def capability(host):
    return host.dataset_private_context()['capability']


def review_result(host, raw):
    result = host.as_dict(raw)
    # as_dict formats Tcl list objects as exact strings. Do not normalize these
    # tokens into Python lists or reinterpret their internal representation.
    result['dataset_revisions'] = {str(k): str(v) for k, v in host.as_dict(result['dataset_revisions']).items()}
    return bounded(result)


def group_result(host, raw):
    result = host.as_dict(raw)
    result['members'] = [host.as_dict(row) for row in host.as_list(result.get('members', ''))]
    for row in result['members']: row['required'] = bool(int(row['required']))
    result['source'] = {k: host.as_dict(v) for k, v in host.as_dict(result.get('source', '')).items()}
    for key in ('revision', 'created_at'):
        if key in result: result[key] = int(result[key])
    if 'history' in result:
        result['history'] = [host.as_dict(v) for v in host.as_list(result['history'])]
        for event in result['history']:
            event['at'] = int(event['at']); event['revision'] = int(event['revision'])
            event['details'] = host.as_dict(event['details'])
    if 'issues' in result:
        result['issues'] = [host.as_dict(v) for v in host.as_list(result['issues'])]
        for issue in result['issues']:
            if 'required' in issue: issue['required'] = bool(int(issue['required']))
    return bounded(result)


def invoke(host, operation, args):
    bounded(args)
    if operation == 'review' and len(args) == 1 and isinstance(args[0], (list, tuple)):
        if len(args[0]) > 64 or any(not isinstance(x, str) for x in args[0]):
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Review requires 0..64 Dataset IDs')
        return review_result(host, host.call('::GX::datasetGroupProducerReviewV1', capability(host), host.session, args[0]))
    if operation == 'create' and len(args) == 2 and all(isinstance(x, dict) for x in args):
        review = args[1]
        revisions = review.get('dataset_revisions')
        if not isinstance(revisions, dict) or any(not isinstance(k, str) or not isinstance(v, str) for k, v in revisions.items()):
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Group review revisions must remain opaque strings')
        return group_result(host, host.call('::GX::datasetGroupProducerCreateV1', capability(host), host.session, *args))
    if operation == 'get' and len(args) == 1 and isinstance(args[0], str):
        return group_result(host, host.call('::GX::datasetGroupGet', host.session, args[0]))
    if operation == 'list' and not args:
        return bounded([group_result(host, value) for value in host.as_list(host.call('::GX::datasetGroupList', host.session))])
    raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Invalid Dataset Group operation arguments')
