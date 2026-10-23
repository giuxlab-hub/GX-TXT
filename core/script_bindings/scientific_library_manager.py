"""Intentional Library Manager v1 bindings, owned by its existing CORE API.

No administrative dispatcher, provider options or destination writer is exposed.
Three bounded credential operations use only the protected owner's closed data
envelopes, separately from the legacy non-secret error catcher. The shared Bridge
and the manager remain the transport/policy
owners. Scientific JSON text is authoritative; no null/number type guessing.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import json
import math
import re

from gxtxt_script_bridge_server import BridgeError, encode_value

API = 'SCIENTIFIC_LIBRARY_MANAGER_API_v1'
PREFIX = '::GX::ScientificLibraryManagerAPIv1::'
SCRIPT_CAPABILITIES = ['library_discovery', 'public_status', 'explicit_json_results',
                       'data_return_export', 'conditional_entry_mutation', 'restricted_credential_runtime']
# name: (fixed public method, positional argument names, required count)
_OPERATIONS = {
    'api_info': ('apiInfo', (), 0),
    'effective_root': ('libraryRoot', (), 0),
    'list_types': ('listLibraryTypes', (), 0),
    'list_libraries': ('listRegisteredLibraries', (), 0),
    'list_installed_libraries': ('listInstalledLibraries', (), 0),
    'library_info': ('getLibraryInfo', ('library_id',), 1),
    'compatible_libraries': ('queryCompatibleLibraries', ('library_type',), 1),
    'legacy_entries': ('listLibraryEntries', ('library_id',), 1),
    'provider_capabilities': ('getProviderCapabilities', ('library_type',), 1),
    'library_capabilities': ('getLibraryCapabilities', ('library_id',), 1),
    'catalog_page': ('libraryCatalogPage', ('options',), 0),
    'entries_page': ('libraryEntriesPage', ('library_id', 'paging'), 1),
    'entry_info': ('getLibraryEntryInfo', ('library_id', 'entry_id'), 2),
    'search_entries': ('searchLibraryEntries', ('library_id', 'query_json', 'paging'), 2),
    'read_entry': ('readLibraryEntry', ('library_id', 'entry_id'), 2),
    'export_entry': ('exportLibraryEntry', ('library_id', 'entry_id', 'format'), 3),
    'add_entry': ('addLibraryEntry', ('library_id', 'entry_json'), 2),
    'remove_entry': ('removeLibraryEntry', ('library_id', 'entry_id'), 2),
    'credential_status': ('credentialStatus', ('library_id',), 1),
    # This one outward operation composes three CORE-only calls; Submit/Finish
    # are never additional Script operations or caller-controlled method names.
    'credential_unlock': ('credentialPrepare', ('library_id', 'unlock_credential', 'lifetime_seconds'), 2),
    'credential_lock': ('credentialLock', ('library_id',), 1),
}
REGISTRATION = {
    'api_id': API, 'api_version': 1, 'provider_kind': 'core',
    'provider_id': 'scientific_library_manager',
    'documentation_ref': 'docs/api/SCIENTIFIC_LIBRARY_MANAGER_API_v1.md',
    'capabilities': SCRIPT_CAPABILITIES,
    'operations': {
        name: {'name': name, 'summary': 'Intentional Library Manager operation: ' + name,
               'arguments': [{'name': arg, 'kind': 'integer' if arg == 'lifetime_seconds' else 'scalar struct' if arg in ('options', 'paging')
                              else 'explicit JSON text' if arg.endswith('_json') else 'string',
                              **({'sensitive': True} if arg == 'unlock_credential' else {}),
                              'required': index < required} for index, arg in enumerate(arguments)],
               'argument_convention': ', '.join(arguments) or 'no arguments',
               'result_contract': 'schema/result_json struct' if name in {
                   'entries_page', 'entry_info', 'search_entries', 'read_entry',
                   'export_entry', 'add_entry', 'remove_entry'} else 'closed credential status/result_json' if name.startswith('credential_') else 'closed public metadata or IDs',
               'result_convention': 'existing owner public data; no provider config or administrative grant'}
        for name, (_, arguments, required) in _OPERATIONS.items()
    },
}
_CAPABILITIES = ('list_entries', 'entry_info', 'search_entries', 'read_entry',
                 'add_entry', 'remove_entry', 'export_entry', 'verify', 'mutable',
                 'read_only', 'remote', 'external', 'offline_available',
                 'authentication_required', 'library_viewer', 'entry_viewer')
_AUTH = {'not_required', 'unknown', 'locked', 'unlocked', 'authenticated',
         'failed', 'authentication_failed'}
_AVAILABILITY = {'available', 'unavailable', 'unknown', 'temporarily_unavailable'}
_MODES = {'managed', 'external', 'remote'}
_CAP_ENUMS = {
    'capability_schema': {'gxtxt.library_capabilities.v1'},
    'mode': _MODES, 'registry_state': {'installed', 'removed', 'unknown'},
    'declaration_source': {'provider_declaration', 'legacy_managed_contract'},
    'status_source': {'registration_metadata_not_probed', 'provider_status', 'provider_unavailable'},
    'status.availability': _AVAILABILITY,
    'status.read_only': {'0', '1', 'unknown'},
    'status.authentication_required': {'0', '1', 'unknown'},
    'status.authentication_status': _AUTH,
    'reason.inspect': {'', 'Library was removed'}, 'reason.refresh': {''},
}
_CAP_TEXT = {'library_type', 'library_id', 'provider_id', 'provider_version'}
_CAP_BASE = {'capability_schema', 'library_type', 'library_id', 'provider_id',
             'provider_version', 'supported_modes', 'mode', 'registry_state',
             'declaration_source', 'status_source'}
_STATUS = {'status.availability', 'status.read_only', 'status.authentication_required',
           'status.authentication_status', 'status.entry_count', 'reason.inspect', 'reason.refresh'}
_INFO = {'library_id', 'library_type', 'provider_id', 'provider_version', 'display_name',
         'version', 'mode', 'state', 'read_only', 'availability', 'authentication_required',
         'authentication_status', 'entry_count', 'description', 'license', 'rights',
         'installed_at', 'updated_at', 'sha256'}
_INFO_ENUMS = {'mode': _MODES, 'state': {'installed', 'removed', 'unknown'},
               'read_only': {'0', '1', 'unknown'}, 'availability': _AVAILABILITY,
               'authentication_required': {'0', '1', 'unknown'}, 'authentication_status': _AUTH}
_CONTENT = {
    'entries_page': 'gxtxt.library_entry_page.v1', 'search_entries': 'gxtxt.library_entry_page.v1',
    'entry_info': 'gxtxt.library_entry_info.v1', 'read_entry': 'gxtxt.library_entry.v1',
    'export_entry': 'gxtxt.library_entry_export.v1',
    'add_entry': 'gxtxt.library_entry_mutation.v1', 'remove_entry': 'gxtxt.library_entry_mutation.v1',
}
_ERRORS = {'unsupported_operation', 'library_not_found', 'entry_not_found', 'read_only',
           'authentication_required', 'credentials_locked', 'authentication_failed',
           'rate_limited', 'temporarily_unavailable', 'provider_unavailable',
           'invalid_provider_configuration', 'integrity_failure', 'policy_restricted',
           'provider_failure', 'invalid_request', 'invalid_provider_response'}
_MUTATIONS = {'add_entry', 'remove_entry'}
_CREDENTIAL_OPERATIONS = {'credential_status', 'credential_unlock', 'credential_lock'}
_CREDENTIAL_STATES = {'not_required', 'unconfigured', 'locked', 'unlocked', 'failed',
                      'unavailable', 'unknown', 'revoking'}
_CREDENTIAL_SCHEMA = 'gxtxt.library_credential_response.v1'
_CREDENTIAL_OPERATION_SCHEMA = 'gxtxt.library_credential_operation.v1'
_CREDENTIAL_LOCAL_CODES = {'unavailable': 'unsupported_operation',
                           'busy': 'temporarily_unavailable',
                           'transport_failure': 'provider_failure',
                           'stale_context': 'credentials_locked'}
_CREDENTIAL_MESSAGES = {
    'unsupported_operation': 'Protected credential support is unavailable.',
    'invalid_request': 'Credential request is invalid.',
    'library_not_found': 'Credential library is unavailable.',
    'credentials_locked': 'Credential grant is locked.',
    'authentication_required': 'Credential profile is not configured.',
    'authentication_failed': 'Credential unlock failed.',
    'provider_unavailable': 'Credential provider is unavailable.',
    'temporarily_unavailable': 'Credential operation is busy.',
    'invalid_provider_configuration': 'Credential provider configuration is invalid.',
    'integrity_failure': 'Credential profile is unavailable.',
    'policy_restricted': 'Credential operation is not permitted.',
    'provider_failure': 'Credential provider operation failed.',
    'invalid_provider_response': 'Credential result is invalid.',
    'rate_limited': 'Credential operation is temporarily limited.',
    'read_only': 'Credential library is read-only.',
    'entry_not_found': 'Credential library entry is unavailable.',
}
_FRAME_LIMIT = 24 * 1024 * 1024
# Fixed internal catcher, local variables only. The command is a proper Tcl list
# built from the finite owner map, never caller command text or a public route.
_CATCH = (('command',), 'set code [catch {uplevel #0 $command} value options]; list $code $value $options')


def _invalid(message):
    raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', message)


def _failure(code, message, details=None):
    error = {'code': code, 'message': message}
    if details:
        error.update(details)
    raise BridgeError('GXTXT:ScientificLibrary:' + code,
                      json.dumps(error, ensure_ascii=False, allow_nan=False, separators=(',', ':')))


def _text(value, *, provider=False, max_bytes=None):
    if not isinstance(value, str):
        if provider:
            _failure('invalid_provider_response', 'Library public field is not text.')
        _invalid('Library arguments require strings, not implicit conversions.')
    try:
        size = len(value.encode('utf-8'))
    except UnicodeError:
        if provider:
            _failure('invalid_provider_response', 'Library public text is invalid UTF-8.')
        _invalid('Library argument is invalid UTF-8.')
    if max_bytes is not None and size > max_bytes:
        if provider:
            _failure('invalid_provider_response', 'Library public field exceeds its bound.')
        _invalid('Library argument exceeds its bound.')
    return value


def _enum(value, choices):
    value = _text(value, provider=True)
    if value not in choices:
        _failure('invalid_provider_response', 'Library public status is outside its approved vocabulary.')
    return value


def _decimal(value, unknown=False):
    token = _text(value, provider=True)
    if unknown and token == 'unknown':
        return token
    if not re.fullmatch(r'[0-9]+', token):
        _failure('invalid_provider_response', 'Library public count is not exact nonnegative decimal text.')
    return token.lstrip('0') or '0'


def _integer(value, minimum, maximum):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        _invalid('Library limits/offsets require integer scalars.')
    if isinstance(value, float) and (not math.isfinite(value) or not value.is_integer() or abs(value) > 2**53):
        _invalid('Library limit/offset is not an exact integral scalar.')
    number = int(value)
    if not minimum <= number <= maximum:
        _invalid('Library limit/offset is outside its admitted range.')
    return number


def _options(value, paging=False):
    if not isinstance(value, dict):
        _invalid('Library options require a scalar struct/map.')
    allowed = {'limit', 'continuation'} if paging else {'mode', 'query', 'offset', 'limit'}
    if set(value) - allowed:
        _invalid('Library options do not admit provider options, destinations or configuration.')
    out = {}
    for key, item in value.items():
        if key == 'limit':
            out[key] = _integer(item, 1, 200)
        elif key == 'offset':
            out[key] = _integer(item, 0, 2**63 - 1)
        elif key == 'mode':
            if _text(item) not in _MODES | {'all'}:
                _invalid('Unknown Library catalog mode.')
            out[key] = item
        elif key == 'query':
            out[key] = _text(item)
            if len(item) > 1024:
                _invalid('Library catalog query exceeds1024 characters.')
        else:
            out[key] = _text(item)
            if not item or '\0' in item or len(item) > 4096:
                _invalid('Library continuation must be a bounded opaque identifier.')
    return out


def _owner_call(host, method, args, mutation=False):
    command = host.tcl.call('list', PREFIX + method, *(host.tcl_arg(arg) for arg in args))
    parts = host.as_list(host.tcl.call('::apply', _CATCH, command))
    if len(parts) != 3:
        _failure('invalid_provider_response', 'Library owner returned an invalid call envelope.',
                 {'mutation_outcome': 'unknown'} if mutation else None)
    code, result, options = parts
    if str(code) == '0':
        return result
    options = host.as_dict(options)
    error_code = host.as_list(options.get('-errorcode', ''))
    if (len(error_code) == 3 and error_code[:2] == ['GXTXT', 'SCIENTIFIC_LIBRARY_MANAGER']
            and error_code[2] in _ERRORS and '-library_error' in options):
        try:
            detail = host.as_dict(options['-library_error'])
            message = _text(detail.get('message', ''), provider=True)
            if not message or len(message) > 4096:
                _failure('invalid_provider_response', 'Library error has invalid public message.')
            safe = {}
            if detail.get('mutation_outcome') == 'unknown':
                safe['mutation_outcome'] = 'unknown'
            if 'provider_code' in detail:
                safe['provider_code'] = _text(detail['provider_code'], provider=True, max_bytes=1024)
            if 'retry_after_seconds' in detail:
                token = str(detail['retry_after_seconds'])
                retry = float(token)
                if not math.isfinite(retry) or retry < 0:
                    _failure('invalid_provider_response', 'Library retry interval is invalid.')
                safe['retry_after_seconds'] = int(token) if re.fullmatch(r'[0-9]+', token) else retry
        except Exception:
            _failure('invalid_provider_response', 'Library normalized error could not be returned.',
                     {'mutation_outcome': 'unknown'} if mutation else None)
        _failure(error_code[2], message, safe)
    if mutation:
        _failure('provider_failure', 'Library mutation owner failed; reconcile provider state before retry.',
                 {'mutation_outcome': 'unknown'})
    raise BridgeError('GXTXT:ScriptBridge:RemoteError', 'Library Manager public owner call failed.')


def _public_info(host, raw):
    result = {}
    for key, value in host.as_dict(raw).items():
        if key not in _INFO:
            continue
        if key in _INFO_ENUMS:
            result[key] = _enum(value, _INFO_ENUMS[key])
        elif key == 'entry_count':
            result[key] = _decimal(value, True)
        else:
            result[key] = _text(value, provider=True)
    return result


def _capabilities(host, raw, library):
    source = host.as_dict(raw)
    allowed = _CAP_BASE | {'capability.' + name for name in _CAPABILITIES}
    if library:
        allowed |= _STATUS
    result = {}
    for key, value in source.items():
        if key not in allowed:
            continue
        if key in _CAP_ENUMS:
            result[key] = _enum(value, _CAP_ENUMS[key])
        elif key in _CAP_TEXT:
            result[key] = _text(value, provider=True, max_bytes=4096)
        elif key == 'supported_modes':
            modes = _text(value, provider=True).split()
            if not modes or len(modes) != len(set(modes)) or set(modes) - _MODES:
                _failure('invalid_provider_response', 'Library supported modes are invalid.')
            result[key] = modes
        elif key == 'status.entry_count':
            result[key] = _decimal(value, True)
        else:
            token = _enum(value, {'0', '1'})
            result[key] = token == '1'
    if result.get('capability_schema') != 'gxtxt.library_capabilities.v1':
        _failure('invalid_provider_response', 'Library capability schema is unsupported.')
    return result


def _api_info(host, raw):
    info = host.as_dict(raw)
    expected = {'api_name': API, 'api_version': '1', 'registry_version': '1',
                'capability_schema': 'gxtxt.library_capabilities.v1'}
    if any(str(info.get(key)) != value for key, value in expected.items()):
        _failure('invalid_provider_response', 'Library Manager public version/schema is unsupported.')
    return dict(api_name=API, api_version=1, registry_version=1,
                capability_schema='gxtxt.library_capabilities.v1', script_exposure='intentional_subset',
                provider_kind='core', provider_id='scientific_library_manager',
                operations=list(_OPERATIONS), capabilities=list(SCRIPT_CAPABILITIES))


def _catalog(host, raw):
    source = host.as_dict(raw)
    if source.get('schema') != 'gxtxt.library_catalog_page.v1':
        _failure('invalid_provider_response', 'Library catalog schema is unsupported.')
    result = {'schema': source['schema']}
    for key in ('total', 'offset', 'limit', 'count'):
        result[key] = int(_decimal(source[key]))
    if not 1 <= result['limit'] <= 200 or result['count'] > result['limit']:
        _failure('invalid_provider_response', 'Library catalog bounds are invalid.')
    result['mode'] = _enum(source['mode'], _MODES | {'all'})
    result['query'] = _text(source['query'], provider=True)
    result['registry_sha256'] = _text(source['registry_sha256'], provider=True)
    if not re.fullmatch('[0-9a-f]{64}', result['registry_sha256']):
        _failure('invalid_provider_response', 'Library catalog revision is invalid.')
    result['records'] = [_public_info(host, record) for record in host.as_list(source['records'])]
    if len(result['records']) != result['count']:
        _failure('invalid_provider_response', 'Library catalog record count is invalid.')
    return result


def _content(raw, host, operation, library_id):
    result = host.as_dict(raw)
    schema = _CONTENT[operation]
    text = _text(result.get('result_json'), provider=True)
    if len(text.encode('utf-8')) > 16 * 1024 * 1024:
        _failure('invalid_provider_response', 'Library content exceeds its JSON bound.')
    try:
        data = json.loads(text)
    except (ValueError, RecursionError):
        _failure('invalid_provider_response', 'Library content JSON is invalid.')
    if (not isinstance(data, dict) or data.get('schema') != schema
            or result.get('schema') != schema or data.get('library_id') != library_id):
        _failure('invalid_provider_response', 'Library content identity/schema is invalid.')
    return {'schema': schema, 'result_json': text}


def _bounded(result):
    # Exact common transport frame; no private wire format or shared owner edit.
    wire = json.dumps({'ok': True, 'value': encode_value(result)}, ensure_ascii=False,
                      allow_nan=False, separators=(',', ':')).encode('utf-8')
    # The shared server terminates every ordinary JSON response with one LF.
    if len(wire) + 1 > _FRAME_LIMIT:
        _failure('invalid_provider_response', 'Library result exceeds the final Bridge frame bound.')
    return result


class _CredentialFailure(Exception):
    """Private finite classification; never forward a caught exception text."""
    def __init__(self, code='invalid_provider_response', *, argument=False, unknown=False):
        super().__init__('Credential operation failed.')
        self.code = code
        self.argument = argument
        self.unknown = unknown


def _credential_envelope(host, raw, schema):
    envelope = host.as_dict(raw)
    ok = str(envelope.get('ok', ''))
    if ok in {'0', 'false'}:
        # Nonsecret preparation can use the owner's existing fixed error
        # envelope. Native operation failures use the operation schema.
        allowed = {'schema', 'ok', 'code', 'message', 'mutation_outcome'}
        if envelope.get('schema') == _CREDENTIAL_OPERATION_SCHEMA:
            allowed |= {'state', 'operation_ref'}
        if (envelope.get('schema') not in {schema, _CREDENTIAL_SCHEMA}
                or set(envelope) - allowed
                or 'state' in envelope and envelope['state'] != 'failed'
                or 'mutation_outcome' in envelope and envelope['mutation_outcome'] != 'unknown'):
            raise _CredentialFailure()
        code = envelope.get('code')
        if not isinstance(code, str):
            raise _CredentialFailure()
        code = _CREDENTIAL_LOCAL_CODES.get(code, code)
        if code not in _CREDENTIAL_MESSAGES:
            raise _CredentialFailure()
        # Message and optional response reference are deliberately ignored.
        raise _CredentialFailure(code, unknown=envelope.get('mutation_outcome') == 'unknown')
    if envelope.get('schema') != schema or ok not in {'1', 'true'}:
        raise _CredentialFailure()
    return envelope


def _credential_reference(host, raw):
    reference = host.as_dict(raw)
    patterns = {'context_id': r'credential-context-[1-9][0-9]*',
                'generation': r'[0-9a-f]{32}', 'operation_id': r'credential-operation-[1-9][0-9]*'}
    if (set(reference) != set(patterns) or any(not isinstance(reference[key], str)
            or not re.fullmatch(pattern, reference[key]) for key, pattern in patterns.items())):
        raise _CredentialFailure()
    # Independent immutable strings captured ONLY from the validated Prepare.
    return dict(reference)


def _credential_quarantine(host, reference):
    try:
        # Private existing-owner cleanup, exact generation AND operation. Never
        # use a Submit/Finish response as the cleanup target or lock by library.
        host.call(PREFIX + '_credentialQuarantine', reference)
    except BaseException:
        pass


def _credential_final(host, raw, library_id):
    try:
        return _credential_final_data(host, raw, library_id)
    except _CredentialFailure:
        raise
    except BaseException:
        pass
    raise _CredentialFailure()


def _credential_final_data(host, raw, library_id):
    envelope = _credential_envelope(host, raw, _CREDENTIAL_SCHEMA)
    if set(envelope) != {'schema', 'ok', 'result'}:
        raise _CredentialFailure()
    result = host.as_dict(envelope['result'])
    text = result.get('result_json')
    if not isinstance(text, str) or len(text.encode('utf-8')) > 16384:
        raise _CredentialFailure()
    typed = json.loads(text)
    if (type(typed) is not dict or set(typed) != {'library_id', 'configured', 'authentication_required',
            'authentication_status', 'expires_in_seconds', 'cleanup_pending'}
            or typed['library_id'] != library_id
            or any(typed[key] is not None and type(typed[key]) is not bool for key in ('configured', 'authentication_required'))
            or typed['authentication_status'] not in _CREDENTIAL_STATES
            or type(typed['expires_in_seconds']) is not int or not 0 <= typed['expires_in_seconds'] <= 900
            or type(typed['cleanup_pending']) is not bool):
        raise _CredentialFailure()
    if typed['authentication_status'] != 'unlocked' and typed['expires_in_seconds'] != 0:
        raise _CredentialFailure()
    typed['result_json'] = text
    return _bounded(typed)


def _credential_unlock(host, args):
    lifetime = args[2] if len(args) == 3 else 300
    if type(lifetime) is not int or not 1 <= lifetime <= 900 or not isinstance(args[1], str):
        raise _CredentialFailure('invalid_request', argument=True)
    prepared = _credential_envelope(host, host.call(PREFIX + 'credentialPrepare', 'unlock',
        {'library_id': args[0], 'lifetime_seconds': str(lifetime)}), _CREDENTIAL_OPERATION_SCHEMA)
    if set(prepared) != {'schema', 'ok', 'operation_ref', 'state'} or prepared['state'] != 'prepared':
        raise _CredentialFailure()
    reference = _credential_reference(host, prepared['operation_ref'])
    submit_failure = None
    finish_failed = False
    final = None
    try:
        try:
            # Primitive Python validation retains no exception outside this
            # scope. Native owns protected Tcl validation/encoding/framing.
            size = len(args[1].encode('utf-8'))
            if not 12 <= size <= 1024:
                raise _CredentialFailure('invalid_request', argument=True)
            # DIRECT native call. Its COMPLETE Tcl invocation returns here
            # before parsing, quarantine, Finish or any receive/decode occurs.
            submitted = _credential_envelope(host,
                host.call(PREFIX + 'credentialSubmit', reference, args[1]), _CREDENTIAL_OPERATION_SCHEMA)
            if (set(submitted) != {'schema', 'ok', 'operation_ref', 'state'}
                    or submitted['state'] != 'submitted'
                    or _credential_reference(host, submitted['operation_ref']) != reference):
                raise _CredentialFailure()
        except _CredentialFailure as error:
            submit_failure = (error.code, error.argument, error.unknown)
        except UnicodeError:
            submit_failure = ('invalid_request', True, False)
        except BaseException:
            submit_failure = ('provider_failure', False, False)
    finally:
        if submit_failure is not None:
            _credential_quarantine(host, reference)
        try:
            # Even refusal, native arity failure, malformed response or lost
            # Submit return finishes the independently captured operation once.
            final = host.call(PREFIX + 'credentialFinish', reference)
        except BaseException:
            finish_failed = True
    if finish_failed:
        _credential_quarantine(host, reference)
        raise _CredentialFailure('provider_failure')
    if submit_failure is not None:
        code, argument, unknown = submit_failure
        raise _CredentialFailure(code, argument=argument, unknown=unknown)
    final_failure = None
    try:
        return _credential_final(host, final, args[0])
    except _CredentialFailure as error:
        final_failure = (error.code, error.argument, error.unknown)
    except BaseException:
        final_failure = ('invalid_provider_response', False, False)
    _credential_quarantine(host, reference)
    code, argument, unknown = final_failure
    raise _CredentialFailure(code, argument=argument, unknown=unknown)


def _credential_call(host, operation, args):
    """One Script result; complete native Tcl return precedes nonsecret Finish.

    The external Python request/arguments still exist. This is not an external
    RPC return, Python memory erasure, or a successful native/runtime proof.
    """
    failure = None
    try:
        method, names, required = _OPERATIONS[operation]
        if (not required <= len(args) <= len(names) or not isinstance(args[0], str)
                or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', args[0])):
            raise _CredentialFailure('invalid_request', argument=True)
        if operation == 'credential_unlock':
            return _credential_unlock(host, args)
        return _credential_final(host, host.call(PREFIX + method, *args), args[0])
    except _CredentialFailure as error:
        failure = (error.code, error.argument, error.unknown)
    except BaseException:
        failure = ('provider_failure', False, False)
    # Fixed BridgeError raised OUTSIDE every raw/private exception handler.
    # Neither message, context, cause, traceback nor owner reference is copied.
    code, argument, unknown = failure
    if argument:
        _invalid('Credential operation arguments are invalid.')
    _failure(code, _CREDENTIAL_MESSAGES[code], {'mutation_outcome': 'unknown'} if unknown else None)


def cleanup(host):
    # Reuse Host.cleanup's existing binding hook; no shared Bridge edit. The
    # manager's actual managed-owner drain remains a separately reviewed gate.
    try:
        host.call(PREFIX + '_credentialCleanup')
    except BaseException:
        pass


def invoke(host, operation, args):
    if operation in _CREDENTIAL_OPERATIONS:
        return _credential_call(host, operation, args)
    schema = _OPERATIONS.get(operation)
    if schema is None:
        raise BridgeError('GXTXT:ScriptBridge:UnknownOperation', 'Library operation is not script-approved.')
    method, names, required = schema
    if not required <= len(args) <= len(names):
        _invalid('Library operation has invalid argument count.')
    parameters = list(args)
    for index, value in enumerate(parameters):
        name = names[index]
        parameters[index] = _options(value, name == 'paging') if name in ('options', 'paging') else _text(value)
    try:
        raw = _owner_call(host, method, parameters, operation in _MUTATIONS)
    except BridgeError:
        raise
    except Exception:
        if operation in _MUTATIONS:
            _failure('provider_failure', 'Library mutation call failed; reconcile provider state before retry.',
                     {'mutation_outcome': 'unknown'})
        raise BridgeError('GXTXT:ScriptBridge:RemoteError', 'Library Manager public owner call failed.')
    try:
        if operation in _CONTENT:
            result = _content(raw, host, operation, parameters[0])
        elif operation == 'api_info':
            result = _api_info(host, raw)
        elif operation == 'library_info':
            result = _public_info(host, raw)
        elif operation in ('list_libraries', 'list_installed_libraries'):
            result = [_public_info(host, record) for record in host.as_list(raw)]
        elif operation in ('list_types', 'compatible_libraries', 'legacy_entries'):
            result = [_text(value, provider=True) for value in host.as_list(raw)]
        elif operation in ('provider_capabilities', 'library_capabilities'):
            result = _capabilities(host, raw, operation == 'library_capabilities')
        elif operation == 'catalog_page':
            result = _catalog(host, raw)
        else:
            result = _text(raw, provider=True)
        return _bounded(result)
    except BridgeError as error:
        if operation in _MUTATIONS:
            _failure('invalid_provider_response', 'Library mutation receipt could not be returned; reconcile state before retry.',
                     {'mutation_outcome': 'unknown'})
        raise error
    except Exception:
        _failure('invalid_provider_response', 'Library public result could not be returned.',
                 {'mutation_outcome': 'unknown'} if operation in _MUTATIONS else None)
