# SPDX-License-Identifier: GPL-3.0-or-later
"""Exact reviewed additive SDK-v1 compatibility, never admission from age alone."""
import hashlib
from pathlib import Path


# Official independently accepted DEV111-P032 fc672ead2755c316025711b9915fdcd6beef4909.
# These three original files are a single reviewed ABI/operation contract. No
# wildcard old policy, altered adapter, arbitrary SDK text or compiler fallback.
P032 = {
    'sdk_sha256': 'fddbc88d8b9885e88bde6ee225c6b0b039a150be6fbd381c5802f7a8c3258152',
    'adapter_sha256': 'e746d25d628c929e321fc403c4937a14d6d0c587caab5327c2f2e90d47b2aa71',
    'policy_sha256': '7f50f308ba02f1efad783945edaf51ba1a8805c2a92eaa62feecbb894e1dc390',
}
P032_OPERATIONS = frozenset({'source_info', 'source_read', 'progress', 'cancelled',
    'prepare_output', 'output_write', 'output_finish', 'helper_call'})


def sdk_hash_compatible(current_hash, admitted_hash):
    # Parent admission already checks the full exact SDK/adapter/policy tuple.
    # The fixed worker verifies this header version before authored binary load.
    return admitted_hash in {current_hash, P032['sdk_sha256']}


def admit_package(root, built, current, operations):
    native = Path(root) / 'native'
    packaged = {}
    for name, key in [('gxtxt_acquisition_sdk_v1.hpp', 'sdk_sha256'),
                      ('trusted_acquisition_adapter_v1.cpp', 'adapter_sha256'),
                      ('ACQUISITION_SDK_CONTRACT.json', 'policy_sha256')]:
        path = native / name
        info = path.stat(follow_symlinks=False)
        if path.is_symlink() or not path.is_file() or info.st_nlink != 1 or info.st_size > 1048576:
            raise ValueError('Native Acquisition SDK package member is not ordinary and bounded')
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != built.get(key) or actual != built['validation'].get(key):
            raise ValueError('Distributed Acquisition SDK/build receipt differs: ' + name)
        packaged[key] = actual
    if packaged == current:
        return 'current_sdk_v1'
    if packaged == P032 and set(operations).issubset(P032_OPERATIONS):
        return 'DEV111-P032_ACCEPTED_SDK_v1'
    raise ValueError('Native Acquisition SDK/policy is not an admitted compatible contract')
