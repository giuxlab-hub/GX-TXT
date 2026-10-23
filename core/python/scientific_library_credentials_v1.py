"""Private encrypted profile storage for the existing Scientific Library manager.

MAIN503 development source only. This is not a public credential API, registry,
daemon, provider authenticator or runtime lease owner. The manager owns admitted
providers, callers, TTL/process guards, protected pipes, diagnostics and public
error projection. Never serialize this module's private unlock result.

Only ciphertext is written. Crypto is imported lazily in protected operations;
metadata inspection does not make it a dependency of legacy Library operations.
The established AESGCM/Scrypt interface used here is present in cryptography43
source; installed-backend/functionality qualification is deliberately separate.
Mutable buffers are cleared best effort, not a Python-wide zeroization claim.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import base64
import contextlib
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys


_ROOT = 'scientific-library-credentials-v1'
_SCHEMA = 'gxtxt.library_credential_profile.v1'
_KDF = 'scrypt-n131072-r8-p1-l32'
_CIPHER = 'aes-256-gcm'
_MAX_RECORD = 16384
_MAX_PROFILES = 64
_ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z', re.ASCII)
_SHA = re.compile(r'[0-9a-f]{64}\Z', re.ASCII)
_GENERATION = re.compile(r'[0-9a-f]{32}\Z', re.ASCII)
_TEMP = re.compile(r'\.ciphertext-[0-9a-f]{32}\Z', re.ASCII)
_FIELDS = frozenset(('schema', 'profile_id', 'provider_id', 'generation',
                     'kdf', 'salt_b64', 'cipher', 'nonce_b64', 'ciphertext_b64'))
_CODES = frozenset(('invalid_request', 'authentication_required',
                    'authentication_failed', 'integrity_failure',
                    'temporarily_unavailable', 'unsupported_operation',
                    'provider_failure'))
_REASONS = frozenset(('invalid_input', 'missing', 'unsafe_storage', 'malformed',
                      'revision_mismatch', 'provider_mismatch', 'profile_limit',
                      'record_limit', 'busy', 'backend_unavailable',
                      'backend_failure', 'authentication_failed', 'io_failure',
                      'recovery_required'))


class ProfileError(Exception):
    """Finite PRIVATE classification; callers must not forward traceback/options.

    ``reason == 'missing'`` distinguishes absent configuration from unsafe or
    malformed storage for the manager's truthful status projection. No supplied
    identifier, path, credential or backend exception is included in the text.
    """
    def __init__(self, code, reason, mutation_outcome=None):
        self.code = code if code in _CODES else 'provider_failure'
        self.reason = reason if reason in _REASONS else 'io_failure'
        self.mutation_outcome = ('unknown' if mutation_outcome == 'unknown'
                                 else None)
        super().__init__('Credential profile operation failed.')


def _fail(code, reason, unknown=False):
    raise ProfileError(code, reason, 'unknown' if unknown else None) from None


def _io_failure(exc, unknown=False):
    if exc.errno in (errno.EACCES, errno.EPERM, errno.ELOOP, errno.ENOTDIR,
                     errno.EISDIR):
        _fail('integrity_failure', 'unsafe_storage', unknown)
    _fail('temporarily_unavailable', 'io_failure', unknown)


def _identifier(value):
    if type(value) is not str or _ID.fullmatch(value) is None:
        _fail('invalid_request', 'invalid_input')
    return value


def _revision(value):
    if type(value) is not str or _SHA.fullmatch(value) is None:
        _fail('invalid_request', 'invalid_input')
    return value


def _text_bytes(value, minimum, maximum):
    if type(value) is not str:
        _fail('invalid_request', 'invalid_input')
    try:
        encoded = value.encode('utf-8', errors='strict')
    except UnicodeError:
        _fail('invalid_request', 'invalid_input')
    if not minimum <= len(encoded) <= maximum:
        _fail('invalid_request', 'invalid_input')
    return encoded


def _clear(value):
    if isinstance(value, bytearray):
        value[:] = b'\0' * len(value)


def _json_bytes(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False,
                      sort_keys=True, separators=(',', ':')).encode('utf-8')


def _pairs(items):
    out = {}
    for key, value in items:
        if key in out:
            _fail('integrity_failure', 'malformed')
        out[key] = value
    return out


def _constant(_value):
    _fail('integrity_failure', 'malformed')


def _parse_json(raw):
    try:
        return json.loads(raw.decode('utf-8', errors='strict'),
                          object_pairs_hook=_pairs, parse_constant=_constant)
    except ProfileError:
        raise
    except (ValueError, UnicodeError, RecursionError, TypeError):
        _fail('integrity_failure', 'malformed')


def _decode64(value, size=None):
    if type(value) is not str or len(value) > _MAX_RECORD:
        _fail('integrity_failure', 'malformed')
    try:
        result = base64.b64decode(value.encode('ascii'), validate=True)
    except (ValueError, UnicodeError):
        _fail('integrity_failure', 'malformed')
    if base64.b64encode(result).decode('ascii') != value:
        _fail('integrity_failure', 'malformed')
    if size is not None and len(result) != size:
        _fail('integrity_failure', 'malformed')
    return result


def _backend():
    # No imports or backend capability work on ordinary module/metadata use.
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
        from cryptography.exceptions import InvalidTag, UnsupportedAlgorithm
    except Exception:
        _fail('unsupported_operation', 'backend_unavailable')
    return AESGCM, Scrypt, InvalidTag, UnsupportedAlgorithm


def _derive(Scrypt, password, salt):
    # Fixed parameters only. No file header can request an arbitrary KDF cost.
    return bytearray(Scrypt(salt=salt, length=32, n=131072, r=8, p=1)
                     .derive(bytes(password)))


def _header(record):
    return {key: value for key, value in record.items()
            if key != 'ciphertext_b64'}


def _metadata(record, raw):
    return dict(profile_id=record['profile_id'], provider_id=record['provider_id'],
                generation=record['generation'],
                revision=hashlib.sha256(raw).hexdigest())


def _record(raw, profile_id):
    value = _parse_json(raw)
    if (type(value) is not dict or set(value) != _FIELDS
            or any(type(item) is not str for item in value.values())):
        _fail('integrity_failure', 'malformed')
    if (value['schema'] != _SCHEMA or value['profile_id'] != profile_id
            or _ID.fullmatch(value['profile_id']) is None
            or _ID.fullmatch(value['provider_id']) is None
            or _GENERATION.fullmatch(value['generation']) is None
            or value['kdf'] != _KDF or value['cipher'] != _CIPHER):
        _fail('integrity_failure', 'malformed')
    _decode64(value['salt_b64'], 16)
    _decode64(value['nonce_b64'], 12)
    if len(_decode64(value['ciphertext_b64'])) < 16:
        _fail('integrity_failure', 'malformed')
    return value


def _stamp(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


class ProfileStore:
    """Private storage/CAS only; no secret-bearing persistent object state.

    Configuration's trusted absolute file path derives the sibling directory.
    Ancestors may be owned by root or the effective user, but must not be
    writable by another user/group. The private directory/files require the
    effective UID and exact0700/0600 modes. Never chmod an existing path.
    """
    def __init__(self, configuration_file: Path):
        if not isinstance(configuration_file, (str, Path)):
            _fail('invalid_request', 'invalid_input')
        try:
            path = Path(configuration_file)
            text = str(path)
            encoded = text.encode('utf-8', errors='strict')
        except (ValueError, UnicodeError, TypeError):
            _fail('invalid_request', 'invalid_input')
        if (not path.is_absolute() or '..' in path.parts or '\0' in text
                or len(encoded) > 4096 or len(path.parts) > 256
                or path.name in ('', '.', '..')):
            _fail('invalid_request', 'invalid_input')
        self._parent = path.parent
        self._ancestor_identity = None
        self._root_identity = None

    @staticmethod
    def _platform():
        if (not sys.platform.startswith('linux') or os.name != 'posix'
                or not hasattr(os, 'O_NOFOLLOW')
                or not hasattr(os, 'O_DIRECTORY')):
            _fail('unsupported_operation', 'backend_unavailable')

    @staticmethod
    def _directory(info, private=False):
        if not stat.S_ISDIR(info.st_mode):
            _fail('integrity_failure', 'unsafe_storage')
        if private:
            if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
                _fail('integrity_failure', 'unsafe_storage')
        elif info.st_uid not in (0, os.geteuid()) or info.st_mode & 0o022:
            _fail('integrity_failure', 'unsafe_storage')

    @staticmethod
    def _file(info):
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1):
            _fail('integrity_failure', 'unsafe_storage')

    def _parent_fd(self):
        self._platform()
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        descriptor = None
        try:
            descriptor = os.open('/', flags)
            info = os.fstat(descriptor)
            self._directory(info)
            identity = [(info.st_dev, info.st_ino)]
            for component in self._parent.parts[1:]:
                child = os.open(component, flags, dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
                info = os.fstat(descriptor)
                self._directory(info)
                identity.append((info.st_dev, info.st_ino))
            identity = tuple(identity)
            if (self._ancestor_identity is not None
                    and identity != self._ancestor_identity):
                _fail('integrity_failure', 'unsafe_storage')
            self._ancestor_identity = identity
            result = descriptor
            descriptor = None
            return result
        except OSError as exc:
            _io_failure(exc)
        finally:
            if descriptor is not None:
                os.close(descriptor)

    def _anchor(self, descriptor):
        parent = self._parent_fd()
        try:
            current = os.stat(_ROOT, dir_fd=parent, follow_symlinks=False)
            held = os.fstat(descriptor)
            self._directory(current, True)
            self._directory(held, True)
            if ((current.st_dev, current.st_ino) != (held.st_dev, held.st_ino)
                    or (held.st_dev, held.st_ino) != self._root_identity):
                _fail('integrity_failure', 'unsafe_storage')
        finally:
            os.close(parent)

    @contextlib.contextmanager
    def _root(self, create=False):
        parent = self._parent_fd()
        descriptor = None
        created = False
        try:
            flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
            try:
                descriptor = os.open(_ROOT, flags, dir_fd=parent)
            except FileNotFoundError:
                if self._root_identity is not None:
                    _fail('integrity_failure', 'unsafe_storage')
                if not create:
                    yield None
                    return
                try:
                    os.mkdir(_ROOT, 0o700, dir_fd=parent)
                    created = True
                    os.fsync(parent)
                except FileExistsError:
                    pass  # A concurrent owner created it; verify, never repair.
                descriptor = os.open(_ROOT, flags, dir_fd=parent)
            info = os.fstat(descriptor)
            self._directory(info, True)
            identity = (info.st_dev, info.st_ino)
            if self._root_identity is not None and self._root_identity != identity:
                _fail('integrity_failure', 'unsafe_storage')
            self._root_identity = identity
            self._anchor(descriptor)
            if created:
                # Only this successful mkdir owner may initialize the lock.
                # Existing or concurrently initialized roots are never repaired.
                lock = os.open('.registry.lock', os.O_RDWR | os.O_NOFOLLOW |
                               os.O_CLOEXEC | os.O_NONBLOCK | os.O_CREAT |
                               os.O_EXCL, 0o600, dir_fd=descriptor)
                try:
                    self._file(os.fstat(lock))
                    os.fsync(lock)
                finally:
                    os.close(lock)
                os.fsync(descriptor)
                self._anchor(descriptor)
            yield descriptor
        finally:
            if descriptor is not None:
                os.close(descriptor)
            os.close(parent)

    @contextlib.contextmanager
    def _locked(self, create=False):
        # Same flock/exclusive-lock algorithm as the existing manager locked();
        # private fd-relative hardening and nonblocking busy policy only.
        self._platform()
        import fcntl
        with self._root(create) as directory:
            if directory is None:
                yield None
                return
            flags = os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK
            try:
                lock = os.open('.registry.lock', flags, 0o600, dir_fd=directory)
            except FileNotFoundError:
                # Cold inspection/hold never repairs or creates store files.
                _fail('integrity_failure', 'unsafe_storage')
            try:
                lock_info = os.fstat(lock)
                self._file(lock_info)
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    _fail('temporarily_unavailable', 'busy')
                self._anchor(directory)
                current = os.stat('.registry.lock', dir_fd=directory, follow_symlinks=False)
                self._file(current)
                if (current.st_dev, current.st_ino) != (lock_info.st_dev, lock_info.st_ino):
                    _fail('integrity_failure', 'unsafe_storage')
                yield directory
                self._anchor(directory)
                current = os.stat('.registry.lock', dir_fd=directory, follow_symlinks=False)
                self._file(current)
                if (current.st_dev, current.st_ino) != (lock_info.st_dev, lock_info.st_ino):
                    _fail('integrity_failure', 'unsafe_storage')
            finally:
                with contextlib.suppress(OSError):
                    fcntl.flock(lock, fcntl.LOCK_UN)
                os.close(lock)

    def _read(self, directory, profile_id):
        if directory is None:
            _fail('authentication_required', 'missing')
        name = profile_id + '.json'
        try:
            descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW |
                                 os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=directory)
        except FileNotFoundError:
            _fail('authentication_required', 'missing')
        try:
            before = os.fstat(descriptor)
            self._file(before)
            if before.st_size > _MAX_RECORD:
                _fail('integrity_failure', 'malformed')
            chunks = []
            count = 0
            while count <= _MAX_RECORD:
                chunk = os.read(descriptor, _MAX_RECORD + 1 - count)
                if not chunk:
                    break
                chunks.append(chunk)
                count += len(chunk)
            if count > _MAX_RECORD:
                _fail('integrity_failure', 'malformed')
            raw = b''.join(chunks)
            after = os.fstat(descriptor)
            current = os.stat(name, dir_fd=directory, follow_symlinks=False)
            if _stamp(before) != _stamp(after) or _stamp(after) != _stamp(current):
                _fail('integrity_failure', 'unsafe_storage')
            value = _record(raw, profile_id)
            return value, raw, _metadata(value, raw)
        finally:
            os.close(descriptor)

    def _names(self, directory):
        names = []
        with os.scandir(directory) as entries:
            count = 0
            for entry in entries:
                count += 1
                if count > _MAX_PROFILES + 1:
                    _fail('integrity_failure', 'profile_limit')
                if entry.name == '.registry.lock':
                    continue
                if _TEMP.fullmatch(entry.name):
                    # A prior uncertain write is evidence, not an auto-cleanup
                    # target. Refuse enumeration/create until owner recovery.
                    _fail('integrity_failure', 'recovery_required')
                if not entry.name.endswith('.json'):
                    _fail('integrity_failure', 'unsafe_storage')
                profile_id = entry.name[:-5]
                if _ID.fullmatch(profile_id) is None:
                    _fail('integrity_failure', 'unsafe_storage')
                names.append(profile_id)
                if len(names) > _MAX_PROFILES:
                    _fail('integrity_failure', 'profile_limit')
        return sorted(names)

    def list_profiles(self):
        try:
            with self._locked() as directory:
                if directory is None:
                    return []
                return [self._read(directory, name)[2]
                        for name in self._names(directory)]
        except OSError as exc:
            _io_failure(exc)

    def inspect(self, profile_id):
        profile_id = _identifier(profile_id)
        try:
            with self._locked() as directory:
                return self._read(directory, profile_id)[2]
        except OSError as exc:
            _io_failure(exc)

    def _encrypted(self, profile_id, provider_id, unlock_utf8, secret_utf8):
        password = bytearray(_text_bytes(unlock_utf8, 12, 1024))
        key = None
        try:
            _text_bytes(secret_utf8, 1, 4096)
            plaintext = _json_bytes(dict(secret_utf8=secret_utf8))
            header = dict(schema=_SCHEMA, profile_id=profile_id,
                          provider_id=provider_id, generation=secrets.token_hex(16),
                          kdf=_KDF, salt_b64=base64.b64encode(os.urandom(16)).decode('ascii'),
                          cipher=_CIPHER,
                          nonce_b64=base64.b64encode(os.urandom(12)).decode('ascii'))
            # JSON escaping can expand an otherwise admitted UTF8 secret. The
            # exact ciphertext envelope cap still applies before KDF work.
            estimate = dict(header, ciphertext_b64=base64.b64encode(
                b'\0' * (len(plaintext) + 16)).decode('ascii'))
            if len(_json_bytes(estimate)) > _MAX_RECORD:
                _fail('invalid_request', 'record_limit')
            AESGCM, Scrypt, _InvalidTag, UnsupportedAlgorithm = _backend()
            try:
                key = _derive(Scrypt, password, _decode64(header['salt_b64'], 16))
                ciphertext = AESGCM(bytes(key)).encrypt(
                    _decode64(header['nonce_b64'], 12), plaintext, _json_bytes(header))
            except UnsupportedAlgorithm:
                _fail('unsupported_operation', 'backend_unavailable')
            except Exception:
                _fail('provider_failure', 'backend_failure')
            raw = _json_bytes(dict(header, ciphertext_b64=base64.b64encode(ciphertext).decode('ascii')))
            if len(raw) > _MAX_RECORD:
                _fail('invalid_request', 'record_limit')
            return raw
        finally:
            _clear(key)
            _clear(password)

    def _write(self, profile_id, expected_revision, provider_id, raw, create):
        temporary = None
        temporary_identity = None
        directory = None
        attempted = False
        try:
            with self._locked(create=create) as directory:
                if directory is None:
                    _fail('authentication_required', 'missing')
                if create:
                    try:
                        self._read(directory, profile_id)
                    except ProfileError as exc:
                        if exc.reason != 'missing':
                            raise
                    else:
                        _fail('integrity_failure', 'revision_mismatch')
                    if len(self._names(directory)) >= _MAX_PROFILES:
                        _fail('invalid_request', 'profile_limit')
                else:
                    _value, _old_raw, old = self._read(directory, profile_id)
                    if old['revision'] != expected_revision:
                        _fail('integrity_failure', 'revision_mismatch')
                    if old['provider_id'] != provider_id:
                        _fail('integrity_failure', 'provider_mismatch')
                temporary = '.ciphertext-' + secrets.token_hex(16)
                descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT |
                                     os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                                     0o600, dir_fd=directory)
                try:
                    info = os.fstat(descriptor)
                    temporary_identity = (info.st_dev, info.st_ino)
                    self._file(info)
                    offset = 0
                    while offset < len(raw):
                        written = os.write(descriptor, raw[offset:])
                        if written <= 0:
                            _fail('temporarily_unavailable', 'io_failure')
                        offset += written
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
                self._anchor(directory)
                name = profile_id + '.json'
                attempted = True
                if create:
                    try:
                        os.link(temporary, name, src_dir_fd=directory,
                                dst_dir_fd=directory, follow_symlinks=False)
                    except FileExistsError:
                        attempted = False  # atomic create-only known refusal
                        _fail('integrity_failure', 'revision_mismatch')
                    info = os.stat(temporary, dir_fd=directory, follow_symlinks=False)
                    if (info.st_dev, info.st_ino) != temporary_identity:
                        _fail('integrity_failure', 'unsafe_storage', True)
                    os.unlink(temporary, dir_fd=directory)
                else:
                    os.replace(temporary, name, src_dir_fd=directory,
                               dst_dir_fd=directory)
                temporary = None
                os.fsync(directory)
                self._anchor(directory)
                _value, observed, result = self._read(directory, profile_id)
                if observed != raw:
                    _fail('integrity_failure', 'revision_mismatch', True)
                return result
        except ProfileError as exc:
            if attempted and exc.mutation_outcome is None:
                _fail(exc.code, exc.reason, True)
            raise
        except OSError as exc:
            _io_failure(exc, attempted)
        finally:
            # Root fd is closed by _locked before this finally. Cleanup only
            # an owned precommit ciphertext temp via a newly validated anchor.
            if temporary is not None and not attempted and temporary_identity is not None:
                try:
                    with self._locked() as current:
                        if current is not None:
                            info = os.stat(temporary, dir_fd=current, follow_symlinks=False)
                            if (info.st_dev, info.st_ino) == temporary_identity:
                                os.unlink(temporary, dir_fd=current)
                                os.fsync(current)
                except (OSError, ProfileError):
                    pass  # Preserve ciphertext evidence; never scan/sweep.

    def create(self, profile_id, expected_revision, provider_id, unlock_utf8, secret_utf8):
        self._platform()
        profile_id = _identifier(profile_id)
        provider_id = _identifier(provider_id)
        if expected_revision != 'absent':
            _fail('invalid_request', 'invalid_input')
        try:
            raw = self._encrypted(profile_id, provider_id, unlock_utf8, secret_utf8)
        except OSError as exc:
            _io_failure(exc)
        return self._write(profile_id, expected_revision, provider_id, raw, True)

    def replace(self, profile_id, expected_revision, provider_id, unlock_utf8, secret_utf8):
        self._platform()
        profile_id = _identifier(profile_id)
        provider_id = _identifier(provider_id)
        expected_revision = _revision(expected_revision)
        try:
            raw = self._encrypted(profile_id, provider_id, unlock_utf8, secret_utf8)
        except OSError as exc:
            _io_failure(exc)
        return self._write(profile_id, expected_revision, provider_id, raw, False)

    def delete(self, profile_id, expected_revision):
        profile_id = _identifier(profile_id)
        expected_revision = _revision(expected_revision)
        attempted = False
        try:
            with self._locked() as directory:
                _value, _raw, metadata = self._read(directory, profile_id)
                if metadata['revision'] != expected_revision:
                    _fail('integrity_failure', 'revision_mismatch')
                self._anchor(directory)
                attempted = True
                os.unlink(profile_id + '.json', dir_fd=directory)
                os.fsync(directory)
                self._anchor(directory)
                return dict(profile_id=profile_id, deleted=True,
                            previous_revision=expected_revision)
        except ProfileError as exc:
            if attempted and exc.mutation_outcome is None:
                _fail(exc.code, exc.reason, True)
            raise
        except OSError as exc:
            _io_failure(exc, attempted)

    def unlock(self, profile_id, unlock_utf8):
        """PRIVATE return: (metadata, bytearray secret); manager owns its lease."""
        profile_id = _identifier(profile_id)
        password = bytearray(_text_bytes(unlock_utf8, 12, 1024))
        key = None
        secret = None
        complete = False
        try:
            with self._locked() as directory:
                value, _raw, metadata = self._read(directory, profile_id)
                AESGCM, Scrypt, InvalidTag, UnsupportedAlgorithm = _backend()
                try:
                    key = _derive(Scrypt, password, _decode64(value['salt_b64'], 16))
                    plaintext = AESGCM(bytes(key)).decrypt(
                        _decode64(value['nonce_b64'], 12),
                        _decode64(value['ciphertext_b64']), _json_bytes(_header(value)))
                except InvalidTag:
                    _fail('authentication_failed', 'authentication_failed')
                except UnsupportedAlgorithm:
                    _fail('unsupported_operation', 'backend_unavailable')
                except Exception:
                    _fail('provider_failure', 'backend_failure')
                decoded = _parse_json(plaintext)
                if type(decoded) is not dict or set(decoded) != {'secret_utf8'}:
                    _fail('integrity_failure', 'malformed')
                try:
                    secret = bytearray(_text_bytes(decoded['secret_utf8'], 1, 4096))
                except ProfileError:
                    _fail('integrity_failure', 'malformed')
                if self._read(directory, profile_id)[2] != metadata:
                    _fail('integrity_failure', 'revision_mismatch')
            complete = True
            return metadata, secret
        except OSError as exc:
            _io_failure(exc)
        finally:
            _clear(password)
            _clear(key)
            if not complete:
                _clear(secret)

    @contextlib.contextmanager
    def hold(self, profile_id, expected_revision):
        """Retain the same profile lock for ONE manager-bounded provider call.

        The fixed directory flock serializes ALL profiles in this store, with
        nonblocking contention; it does not promise per-profile concurrency.
        It is separate from the scientific Library registry lock.
        The manager additionally compares provider/generation and its complete
        grant identity, enforces <=10seconds/remaining TTL, and owns all errors
        from the yielded provider body. This store creates no timer/executor.
        """
        profile_id = _identifier(profile_id)
        expected_revision = _revision(expected_revision)
        try:
            with self._locked() as directory:
                _value, _raw, metadata = self._read(directory, profile_id)
                if metadata['revision'] != expected_revision:
                    _fail('integrity_failure', 'revision_mismatch')
                yield metadata
                if self._read(directory, profile_id)[2] != metadata:
                    _fail('integrity_failure', 'revision_mismatch')
        except OSError as exc:
            _io_failure(exc)
