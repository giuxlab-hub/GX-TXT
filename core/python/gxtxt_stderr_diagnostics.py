# SPDX-License-Identifier: GPL-3.0-or-later
"""Optional trusted duplication into the one CORE collector.

No imports of native bindings, IPC, queues, threads or filesystem writes occur
when the host supplied no active-generation descriptor. The existing source
drain is authoritative and must continue regardless of optional emit outcomes.
"""
import os
from pathlib import Path
import importlib.util


def optional_producer():
    descriptor = os.environ.get('GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR', '')
    if not descriptor:
        return None
    binding = Path(__file__).resolve().parents[1] / 'diagnostics' / 'producer_v1.py'
    library = binding.parent / 'bin' / 'gxdiagnostics.so'
    if os.environ.get('GXTXT_STDERR_DIAGNOSTICS_LIBRARY') != str(library):
        return None
    try:
        spec = importlib.util.spec_from_file_location('_gxtxt_diagnostics_producer_v1', binding)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        producer = module.Producer(str(library), descriptor)
        if producer.attach_result:
            producer.close()
            return None
        return producer
    except (OSError, ValueError, RuntimeError, ImportError):
        # Optional diagnostic failure cannot reject a scientific launch.
        return None


def emit_chunks(producer, payload, **origin):
    if producer is None or not producer.handle:
        return
    for index, offset in enumerate(range(0, len(payload), 32768)):
        result=producer.emit(payload[offset:offset + 32768], chunk_index=index, **origin)
        if result in (1,4):
            # Revoked/off or broken transport is terminal for this launch.
            # Original streams keep draining; no polling or reconnect loop.
            producer.close()
            break
